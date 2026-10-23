import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../workout/exercise_card.dart' show fmtNum;
import 'models.dart';
import 'nutrition_repository.dart';

/// Diálogo para crear un alimento propio. Devuelve el alimento creado.
Future<Food?> showFoodForm(BuildContext context, {String initialName = ''}) =>
    showDialog<Food>(context: context, builder: (_) => _FoodForm(initialName: initialName));

class _FoodForm extends ConsumerStatefulWidget {
  const _FoodForm({required this.initialName});
  final String initialName;

  @override
  ConsumerState<_FoodForm> createState() => _FoodFormState();
}

class _FoodFormState extends ConsumerState<_FoodForm> {
  late final _name = TextEditingController(text: widget.initialName);
  final _kcal = TextEditingController(), _protein = TextEditingController(), _carbs = TextEditingController();
  final _fat = TextEditingController(), _portion = TextEditingController(text: '100');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat, _portion]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final input = foodInput(name: _name.text, kcal: _kcal.text, protein: _protein.text, carbs: _carbs.text, fat: _fat.text, portion: _portion.text);
    if (input.error != null) {
      setState(() => _error = input.error);
      return;
    }
    setState(() => _saving = true);
    try {
      final f = await ref.read(nutritionRepositoryProvider).createFood(input.json!);
      refreshFoods(ref);
      if (mounted) Navigator.pop(context, f);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiMessage(e);
        });
      }
    }
  }

  Widget _num(TextEditingController c, String label, {String suffix = 'g'}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: const Text('Alimento propio'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            autofocus: widget.initialName.isEmpty,
            maxLength: 160,
            decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Skyr natural marca X', counterText: ''),
          ),
          const SizedBox(height: 12),
          Text('Por cada 100 g, como en la etiqueta', style: t.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _num(_kcal, 'Calorías', suffix: 'kcal')),
            const SizedBox(width: 8),
            Expanded(child: _num(_protein, 'Proteína')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _num(_carbs, 'Carbohidratos')),
            const SizedBox(width: 8),
            Expanded(child: _num(_fat, 'Grasa')),
          ]),
          const SizedBox(height: 12),
          _num(_portion, 'Ración habitual'),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: t.colorScheme.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Crear')),
      ],
    );
  }
}

/// Hoja para elegir un alimento (o crear uno). Devuelve el elegido.
Future<Food?> showFoodPicker(BuildContext context, {Set<String> exclude = const {}}) => showModalBottomSheet<Food>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FoodPicker(exclude: exclude),
    );

class _FoodPicker extends ConsumerStatefulWidget {
  const _FoodPicker({required this.exclude});
  final Set<String> exclude;

  @override
  ConsumerState<_FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends ConsumerState<_FoodPicker> {
  String _query = '', _typed = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    final f = await showFoodForm(context, initialName: _typed.trim());
    if (f != null && mounted) Navigator.pop(context, f);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar alimento'),
                onChanged: (v) {
                  _typed = v;
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 250), () => setState(() => _query = v.trim()));
                },
              ),
            ),
            ListTile(leading: const Icon(Icons.add), title: const Text('Crear alimento propio'), onTap: _create),
            const Divider(height: 1),
            Expanded(
              child: ref.watch(foodSearchProvider(_query)).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text(apiMessage(e), textAlign: TextAlign.center)),
                    data: (all) {
                      final foods = [for (final f in all) if (!widget.exclude.contains(f.id)) f];
                      if (foods.isEmpty) return const Center(child: Text('No hay alimentos con ese nombre. Puedes crearlo.'));
                      return ListView(children: [
                        for (final f in foods)
                          ListTile(
                            title: Text(f.name),
                            subtitle: Text(f.mine ? 'Tus alimentos' : f.category),
                            trailing: Text('${fmtNum(f.per100.kcal)} kcal\n${fmtNum(f.per100.protein)} g prot.',
                                textAlign: TextAlign.end, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                            onTap: () => Navigator.pop(context, f),
                          ),
                      ]);
                    },
                  ),
            ),
          ]),
        ),
      ),
    );
  }
}
