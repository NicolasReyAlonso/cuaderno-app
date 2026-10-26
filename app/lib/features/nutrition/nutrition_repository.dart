import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/sync_api.dart' show uuidV4;
import '../../core/local/sync_controller.dart';
import '../../core/local/sync_engine.dart';
import '../body/body_repository.dart' show profileProvider;
import '../workout/workout_repository.dart' show isoDate;
import 'models.dart';

/// Comidas leen y escriben en la base local; la sincronización se encarga del servidor.
class NutritionRepository {
  NutritionRepository(this._engine, this._onChange);
  final SyncEngine _engine;
  final void Function() _onChange;

  Future<T> _write<T>(Future<T> Function() f) async {
    final r = await f();
    _onChange();
    return r;
  }

  /// [json]: lo validado por foodInput. El id lo pone la app («u:» + 12 caracteres, como el servidor).
  Future<Food> createFood(Map<String, dynamic> json) => _write(() async {
        final id = 'u:${uuidV4().replaceAll('-', '').substring(0, 12)}';
        final data = {'category': 'Mis alimentos', ...json};
        await _engine.put('food', id, data);
        return Food.fromSync(id, data);
      });

  Future<void> deleteFood(String id) => _write(() => _engine.remove('food', id));

  /// Crea el plato si no tiene id; si lo tiene, lo sustituye.
  Future<Dish> saveDish(DishDraft d) => _write(() async {
        final id = d.id ?? uuidV4();
        final data = d.toJson();
        await _engine.put('dish', id, data);
        return Dish.fromSync(id, data);
      });

  Future<void> deleteDish(String id) => _write(() => _engine.remove('dish', id));

  /// Apunta [grams] de un alimento o de un plato. Los valores se copian ya calculados para esos gramos:
  /// si luego cambias el alimento o el plato, lo apuntado no cambia.
  Future<void> addItem(DateTime date, String meal, double grams, {required String name, required Per100 per100, String? foodId, String? dishId}) =>
      _write(() => _engine.put('diary_item', uuidV4(), {
            'date': isoDate(date),
            'meal': meal,
            'name': name,
            'food_id': foodId,
            'dish_id': dishId,
            'grams': grams,
            ...per100.entryValues(grams),
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }));

  Future<void> deleteItem(String id) => _write(() => _engine.remove('diary_item', id));
}

final nutritionRepositoryProvider = Provider<NutritionRepository>(
  (ref) => NutritionRepository(ref.watch(syncEngineProvider), () => ref.read(syncControllerProvider.notifier).changed()),
);

/// Alimentos del catálogo, guardados en local con la sincronización (para buscar sin conexión).
final catalogFoodsProvider = StreamProvider<List<Food>>((ref) => ref.watch(localDbProvider).watchMeta('ref_data').map((raw) {
      if (raw == null) return const <Food>[];
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return [for (final f in j['foods'] as List? ?? const []) Food.fromJson(f as Map<String, dynamic>)];
    }));

final myFoodsProvider = Provider<AsyncValue<List<Food>>>((ref) => ref
    .watch(localRecordsProvider('food'))
    .whenData((rows) => [for (final e in rows.entries) Food.fromSync(e.key, e.value)]..sort((a, b) => a.name.compareTo(b.name))));

final foodSearchProvider = Provider.family<AsyncValue<List<Food>>, String>((ref, q) {
  final own = ref.watch(myFoodsProvider);
  final catalog = ref.watch(catalogFoodsProvider);
  if (!own.hasValue || !catalog.hasValue) return const AsyncLoading();
  return AsyncData(searchFoods(own.value!, catalog.value!, q));
});

final dishesProvider = Provider<AsyncValue<List<Dish>>>((ref) => ref
    .watch(localRecordsProvider('dish'))
    .whenData((rows) => [for (final e in rows.entries) Dish.fromSync(e.key, e.value)]..sort((a, b) => a.name.compareTo(b.name))));

final _diaryItemsProvider = StreamProvider.family<List<DiaryItem>, String>((ref, day) => ref
    .watch(localDbProvider)
    .watchDay('diary_item', day)
    .map((rows) => [for (final r in rows) if (r.data != null) DiaryItem.fromSync(r.id, jsonDecode(r.data!) as Map<String, dynamic>)]));

/// El diario de un día con los objetivos del perfil. Se actualiza solo al apuntar o sincronizar.
final diaryDayProvider = Provider.family<AsyncValue<DiaryDay>, DateTime>((ref, date) {
  final items = ref.watch(_diaryItemsProvider(isoDate(date)));
  final profile = ref.watch(profileProvider);
  if (items.hasError) return AsyncError(items.error!, items.stackTrace!);
  if (!items.hasValue || !profile.hasValue) return const AsyncLoading();
  return AsyncData(DiaryDay.build(date, items.value!, kcalTarget: profile.value!.kcalTarget, proteinTarget: profile.value!.proteinTargetG));
});

/// Kcal y proteína del diario por día (para Peso: si un día tiene diario, manda sobre lo escrito a mano).
final diaryTotalsProvider = StreamProvider<Map<String, ({double a, double b})>>(
  (ref) => ref.watch(localDbProvider).watchDailySums('diary_item', 'kcal', 'protein'),
);
