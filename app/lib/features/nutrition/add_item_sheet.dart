import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../workout/exercise_card.dart' show fmtNum;
import 'food_widgets.dart';
import 'models.dart';
import 'nutrition_repository.dart';

/// Lo elegido en la búsqueda: un alimento o un plato, con su ración por defecto.
class _Pick {
  final String name, subtitle;
  final Per100 per100;
  final double portionG;
  final String? foodId, dishId;
  const _Pick({required this.name, required this.subtitle, required this.per100, required this.portionG, this.foodId, this.dishId});

  factory _Pick.food(Food f) => _Pick(
      name: f.name, subtitle: f.mine ? 'Tus alimentos' : f.category, per100: f.per100, portionG: f.defaultPortionG.toDouble(), foodId: f.id);
  factory _Pick.dish(Dish d) =>
      _Pick(name: d.name, subtitle: 'Tu plato · ración de ${d.servingG} g', per100: d.per100, portionG: d.servingG.toDouble(), dishId: d.id);
}

/// Hoja para apuntar algo en el diario de [date]. Devuelve el texto de confirmación si se apuntó.
Future<String?> showAddItemSheet(BuildContext context, DateTime date, String meal) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddItemSheet(date: date, initialMeal: meal),
    );

class _AddItemSheet extends ConsumerStatefulWidget {
  const _AddItemSheet({required this.date, required this.initialMeal});
  final DateTime date;
  final String initialMeal;

  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  late String _meal = widget.initialMeal;
  String _query = '', _typed = '';
  Timer? _debounce;
  _Pick? _pick;
  final _grams = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _grams.dispose();
    super.dispose();
  }

  void _search(String v) {
    _typed = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => setState(() => _query = v.trim()));
  }

  void _choose(_Pick p) => setState(() {
        _pick = p;
        _grams.text = fmtNum(p.portionG);
        _error = null;
      });

  Future<void> _createFood() async {
    final f = await showFoodForm(context, initialName: _typed.trim());
    if (f != null && mounted) _choose(_Pick.food(f));
  }

  Future<void> _add() async {
    final p = _pick!;
    final g = parseGrams(_grams.text);
    if (g == null) {
      setState(() => _error = 'Escribe los gramos con cifras, por ejemplo 120 o 62,5.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(nutritionRepositoryProvider).addItem(widget.date, _meal, g, foodId: p.foodId, dishId: p.dishId);
      ref.invalidate(diaryDayProvider(widget.date));
      if (mounted) Navigator.pop(context, 'Apuntado: ${p.name}, ${fmtNum(g)} g en ${meals.firstWhere((m) => m.$1 == _meal).$2.toLowerCase()}.');
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), // sube sobre el teclado
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (key, label) in meals)
                  ChoiceChip(label: Text(label), selected: _meal == key, onSelected: (_) => setState(() => _meal = key)),
              ]),
            ),
            Expanded(child: _pick == null ? _results(context) : _portion(context, _pick!)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final foods = ref.watch(foodSearchProvider(_query));
    final q = _query.toLowerCase();
    final dishes = (ref.watch(dishesProvider).valueOrNull ?? const <Dish>[])
        .where((d) => q.isEmpty || d.name.toLowerCase().contains(q))
        .toList();

    Widget tile(_Pick p) => ListTile(
          title: Text(p.name),
          subtitle: Text(p.subtitle),
          trailing: Text('${fmtNum(p.per100.kcal)} kcal\n${fmtNum(p.per100.protein)} g prot.',
              textAlign: TextAlign.end, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          onTap: () => _choose(p),
        );

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(text, style: t.textTheme.labelLarge?.copyWith(color: cs.primary)),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          autofocus: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar alimento o plato'),
          onChanged: _search,
        ),
      ),
      ListTile(leading: const Icon(Icons.add), title: const Text('Crear alimento propio'), onTap: _createFood),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text('Valores por 100 g', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ),
      Expanded(
        child: foods.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(apiMessage(e), textAlign: TextAlign.center))),
          data: (found) => found.isEmpty && dishes.isEmpty
              ? const Center(child: Text('No hay nada con ese nombre. Prueba con otra palabra o créalo.'))
              : ListView(children: [
                  if (dishes.isNotEmpty) ...[header('Tus platos'), for (final d in dishes) tile(_Pick.dish(d))],
                  if (found.isNotEmpty) ...[
                    if (dishes.isNotEmpty) header('Alimentos'),
                    for (final f in found) tile(_Pick.food(f)),
                  ],
                ]),
        ),
      ),
    ]);
  }

  Widget _portion(BuildContext context, _Pick p) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final g = parseGrams(_grams.text);
    final v = g == null ? null : p.per100.forGrams(g);
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
      Row(children: [
        IconButton(tooltip: 'Volver a la búsqueda', onPressed: () => setState(() => _pick = null), icon: const Icon(Icons.arrow_back)),
        const SizedBox(width: 4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: t.textTheme.titleMedium),
            Text(p.subtitle, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 120,
          child: TextField(
            controller: _grams,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Gramos', suffixText: 'g'),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _saving ? null : _add(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              v == null ? '—' : '${fmtNum(v.kcal.roundToDouble())} kcal · ${fmtNum((v.protein * 10).round() / 10)} g de proteína',
              style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in const [0.5, 1.0, 1.5, 2.0])
          ActionChip(
            label: Text(f == 1 ? 'Ración (${fmtNum(p.portionG)} g)' : '×${fmtNum(f)}'),
            onPressed: () => setState(() => _grams.text = fmtNum((p.portionG * f).roundToDouble())),
          ),
      ]),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _saving ? null : _add,
        child: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text('Añadir a ${meals.firstWhere((m) => m.$1 == _meal).$2.toLowerCase()}'),
      ),
    ]);
  }
}
