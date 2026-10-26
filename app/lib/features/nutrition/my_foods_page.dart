import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../workout/exercise_card.dart' show fmtNum;
import 'dish_editor_page.dart';
import 'food_widgets.dart';
import 'models.dart';
import 'nutrition_repository.dart';

/// Tus platos y tus alimentos: crear, editar (platos) y borrar.
class MyFoodsPage extends ConsumerWidget {
  const MyFoodsPage({super.key});

  static void _show(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  static Future<bool> _confirm(BuildContext context, String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
          ],
        ),
      ) ==
      true;

  Future<void> _openDish(BuildContext context, Dish? d) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => DishEditorPage(dish: d)));
    if (saved == true && context.mounted) _show(context, 'Plato guardado.');
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String title, Future<void> Function() action) async {
    if (!await _confirm(context, title, 'Lo que ya apuntaste en el diario se queda como está.')) return;
    try {
      await action();
    } catch (e) {
      if (context.mounted) _show(context, apiMessage(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(nutritionRepositoryProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis platos y alimentos'),
          bottom: const TabBar(tabs: [Tab(text: 'Platos'), Tab(text: 'Alimentos')]),
        ),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton.extended(
            onPressed: () => DefaultTabController.of(context).index == 0 ? _openDish(context, null) : showFoodForm(context),
            icon: const Icon(Icons.add),
            label: const Text('Nuevo'),
          ),
        ),
        body: TabBarView(children: [
          _AsyncList<Dish>(
            value: ref.watch(dishesProvider),
            onRetry: () => ref.invalidate(dishesProvider),
            empty: 'Aún no tienes platos. Crea uno con sus ingredientes y raciones.',
            tile: (d) => ListTile(
              title: Text(d.name),
              subtitle: Text('${d.servings} ${d.servings == 1 ? 'ración' : 'raciones'} de ${d.servingG} g · '
                  '${fmtNum((d.totalKcal / d.servings).roundToDouble())} kcal por ración'),
              onTap: () => _openDish(context, d),
              trailing: IconButton(
                tooltip: 'Borrar ${d.name}',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, ref, '¿Borrar «${d.name}»?', () => repo.deleteDish(d.id)),
              ),
            ),
          ),
          _AsyncList<Food>(
            value: ref.watch(myFoodsProvider),
            onRetry: () => ref.invalidate(myFoodsProvider),
            empty: 'Aún no tienes alimentos propios. Crea uno con los valores de su etiqueta.',
            tile: (f) => ListTile(
              title: Text(f.name),
              subtitle: Text('Por 100 g: ${fmtNum(f.per100.kcal)} kcal · ${fmtNum(f.per100.protein)} g prot. · ración ${f.defaultPortionG} g'),
              trailing: IconButton(
                tooltip: 'Borrar ${f.name}',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, ref, '¿Borrar «${f.name}»?', () => repo.deleteFood(f.id)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({required this.value, required this.onRetry, required this.empty, required this.tile});
  final AsyncValue<List<T>> value;
  final VoidCallback onRetry;
  final String empty;
  final Widget Function(T) tile;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(apiMessage(e), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Reintentar')),
          ]),
        ),
        data: (items) => items.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(empty, textAlign: TextAlign.center)))
            : ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  for (final i in items)
                    Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: tile(i))),
                ],
              ),
      );
}
