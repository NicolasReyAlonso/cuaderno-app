import 'dart:convert';

import 'package:cuaderno/core/local/local_db.dart';
import 'package:cuaderno/core/local/sync_api.dart';
import 'package:cuaderno/core/local/sync_controller.dart';
import 'package:cuaderno/core/local/sync_engine.dart';
import 'package:cuaderno/core/local/sync_widgets.dart' show describe;
import 'package:cuaderno/features/body/models.dart';
import 'package:cuaderno/features/nutrition/models.dart';
import 'package:cuaderno/features/nutrition/nutrition_repository.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoServer implements SyncApi {
  @override
  Future<PullPage> pull(int since) => throw const OfflineException();
  @override
  Future<List<PushResult>> push(List<OutboxOp> ops) => throw const OfflineException();
  @override
  Future<Map<String, dynamic>?> reference(String? knownHash) => throw const OfflineException();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late LocalDb db;
  late NutritionRepository repo;
  var changes = 0;

  setUp(() {
    db = LocalDb(NativeDatabase.memory());
    changes = 0;
    repo = NutritionRepository(SyncEngine(db, _NoServer()), () => changes++);
  });
  tearDown(() => db.close());

  test('alimento propio, plato con él y entrada del diario, todo sin servidor', () async {
    final food = await repo.createFood({'name': 'Skyr marca X', 'kcal': 63.0, 'protein': 11.0, 'carbs': 4.0, 'fat': 0.2, 'default_portion_g': 150});
    expect(food.id, matches(RegExp(r'^u:[0-9a-f]{12}$')));
    expect(food.mine, isTrue);

    final dish = await repo.saveDish(DishDraft(name: 'Bol', servings: 2, ingredients: [IngredientDraft.fromFood(food, 300)]));
    final saved = Dish.fromSync(dish.id, decodeData(await db.record('dish', dish.id))!);
    expect((saved.servingG, saved.totalKcal, saved.ingredients.single.foodId), (150, 189.0, food.id));

    await repo.addItem(DateTime(2026, 10, 20), 'desayuno', 150, name: dish.name, per100: dish.per100, dishId: dish.id);
    await repo.addItem(DateTime(2026, 10, 21), 'cena', 100, name: food.name, per100: food.per100, foodId: food.id);
    final day20 = await db.watchDay('diary_item', '2026-10-20').first;
    final item = DiaryItem.fromSync(day20.single.id, jsonDecode(day20.single.data!) as Map<String, dynamic>);
    expect((item.name, item.kcal, item.protein), ('Bol', 94.5, 16.5));
    expect(changes, 4); // cada cambio avisa al sincronizador

    // Todo queda en la cola, en orden: el alimento antes que el plato que lo usa
    expect((await db.select(db.outbox).get()).map((o) => o.entity), ['food', 'dish', 'diary_item', 'diary_item']);

    await repo.deleteItem(item.id);
    expect(await db.watchDay('diary_item', '2026-10-20').first, isEmpty);
  });

  test('búsqueda: tus alimentos y el catálogo guardado en local', () async {
    final container = ProviderContainer(overrides: [localDbProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    await db.setMeta('ref_data', jsonEncode({
      'hash': 'x',
      'foods': [
        {'id': 'b:skyr', 'name': 'Skyr natural', 'category': 'Lácteos', 'kcal': 63, 'protein': 11, 'carbs': 4, 'fat': 0.2, 'default_portion_g': 150},
      ],
    }));
    await repo.createFood({'name': 'Skyr marca X', 'kcal': 60.0, 'protein': 10.0, 'carbs': 4.0, 'fat': 0.0, 'default_portion_g': 150});
    // Esperar a que lleguen los datos de la base a los proveedores
    container.listen(foodSearchProvider('skyr'), (_, __) {});
    await container.read(catalogFoodsProvider.future);
    await container.read(localRecordsProvider('food').future);
    final found = container.read(foodSearchProvider('skyr')).value!;
    expect(found.map((f) => (f.name, f.mine)), [('Skyr marca X', true), ('Skyr natural', false)]);
  });

  test('Peso usa los totales del diario y manda sobre las kcal escritas a mano (como el backend)', () async {
    await repo.addItem(DateTime(2026, 10, 20), 'almuerzo', 407, name: 'Arroz marisco', per100: const Per100(114.8, 7.5, 18, 2), dishId: 'd');
    await repo.addItem(DateTime(2026, 10, 20), 'desayuno', 120, name: 'Plátano', per100: const Per100(89, 1.1, 22.8, 0.3), foodId: 'b:platano');
    final totals = await db.watchDailySums('diary_item', 'kcal', 'protein').first;
    final s = computeSummary([BodyEntry(date: DateTime(2026, 10, 20), weightKg: 98.1, kcal: 9999)], null, const [], diary: totals);
    final row = s.entries.single;
    expect((row.fromDiary, row.kcal, row.weightKg), (true, 574.0, 98.1));
    expect([94.5, 95.5, 94.4, 94.6].map(roundHalfEven), [94, 96, 94, 95]); // como round() de Python
  });

  test('la pantalla de conflictos nombra cada cosa en español', () {
    expect(describe('body_entry', '2026-10-20'), 'Peso y medidas del 20 oct 2026');
    expect(describe('diary_item', 'x', {'name': 'Bol', 'date': '2026-10-20'}), 'Entrada del diario: Bol (20 oct 2026)');
    expect(describe('dish', 'x', {'name': 'Arroz con marisco'}), 'Plato: Arroz con marisco');
    expect(describe('profile', 'me'), 'Punto de partida y objetivos');
  });
}
