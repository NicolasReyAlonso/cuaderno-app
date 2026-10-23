import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../workout/exercise_card.dart' show fmtNum;
import 'food_widgets.dart';
import 'models.dart';
import 'nutrition_repository.dart';

String _kcal(double v) => fmtNum(v.roundToDouble());
String _g(double v) => fmtNum((v * 10).round() / 10);

/// Editor de plato: ingredientes en crudo, raciones y, si lo pesas, el peso ya cocinado.
/// [dish] == null → plato nuevo.
class DishEditorPage extends ConsumerStatefulWidget {
  const DishEditorPage({super.key, this.dish});
  final Dish? dish;

  @override
  ConsumerState<DishEditorPage> createState() => _DishEditorPageState();
}

class _DishEditorPageState extends ConsumerState<DishEditorPage> {
  late final DishDraft _d = widget.dish == null ? DishDraft() : DishDraft.fromDish(widget.dish!);
  bool _dirty = false, _saving = false;
  String? _error;

  void _edit(VoidCallback change) => setState(() {
        change();
        _dirty = true;
        _error = null;
      });

  Future<void> _addIngredient() async {
    final f = await showFoodPicker(context, exclude: {for (final i in _d.ingredients) if (i.foodId != null) i.foodId!});
    if (f != null) _edit(() => _d.ingredients.add(IngredientDraft.fromFood(f, f.defaultPortionG.toDouble())));
  }

  Future<void> _save() async {
    final problem = _d.problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(nutritionRepositoryProvider).saveDish(_d);
      refreshFoods(ref);
      if (!mounted) return;
      _dirty = false;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiMessage(e);
        });
      }
    }
  }

  Future<bool> _confirmLeave() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('¿Salir sin guardar?'),
          content: const Text('Perderás los cambios de este plato.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salir')),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.dish == null ? 'Nuevo plato' : 'Editar plato')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(
                    initialValue: _d.name,
                    maxLength: 160,
                    decoration: const InputDecoration(labelText: 'Nombre del plato', hintText: 'Arroz con marisco', counterText: ''),
                    onChanged: (v) => _edit(() => _d.name = v),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        initialValue: '${_d.servings}',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                        decoration: const InputDecoration(labelText: 'Raciones'),
                        onChanged: (v) => _edit(() => _d.servings = int.tryParse(v) ?? 0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: _d.cookedWeightG == null ? '' : fmtNum(_d.cookedWeightG!),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Peso cocinado (opcional)', suffixText: 'g'),
                        onChanged: (v) => _edit(() => _d.cookedWeightG = v.trim().isEmpty ? null : (parseGrams(v) ?? -1)),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Si pesas el plato ya hecho, la ración se calcula con ese peso; si no, con los ingredientes en crudo.',
                      style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  Text('Ingredientes en crudo', style: t.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final i in _d.ingredients)
                    Padding(
                      key: ObjectKey(i),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(i.name, style: i.foodId == null ? TextStyle(color: cs.error) : null),
                            Text(
                              i.foodId == null ? 'Este alimento ya no existe.' : '${_kcal(i.kcal)} kcal · ${_g(i.protein)} g prot.',
                              style: t.textTheme.bodySmall?.copyWith(color: i.foodId == null ? cs.error : cs.onSurfaceVariant),
                            ),
                          ]),
                        ),
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            initialValue: fmtNum(i.grams),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Gramos', suffixText: 'g'),
                            onChanged: (v) => _edit(() => i.grams = parseGrams(v) ?? 0),
                          ),
                        ),
                        IconButton(tooltip: 'Quitar ${i.name}', onPressed: () => _edit(() => _d.ingredients.remove(i)), icon: const Icon(Icons.close)),
                      ]),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(onPressed: _addIngredient, icon: const Icon(Icons.add), label: const Text('Añadir ingrediente')),
                  ),
                  const SizedBox(height: 12),
                  Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(
                        _d.servings > 0
                            ? 'Ración: ${_d.servingG} g · ${_kcal(_d.kcalPerServing)} kcal · ${_g(_d.proteinPerServing)} g prot.'
                            : 'Pon cuántas raciones salen.',
                        style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text('Todo el plato: ${_kcal(_d.kcal)} kcal · ${_g(_d.protein)} g prot. · ${_g(_d.weight)} g',
                          style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
            ),
          ],
        ),
        bottomNavigationBar: Material(
          color: cs.surface,
          elevation: 3,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(children: [
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Guardar plato'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error ?? 'Lo que ya apuntaste en el diario no cambia al editar el plato.',
                    style: TextStyle(color: _error != null ? cs.error : cs.onSurfaceVariant, fontSize: 13),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
