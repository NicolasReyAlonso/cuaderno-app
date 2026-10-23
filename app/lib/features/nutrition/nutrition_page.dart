import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../workout/exercise_card.dart' show fmtNum, shortDate;
import 'add_item_sheet.dart';
import 'my_foods_page.dart';
import 'models.dart';
import 'nutrition_repository.dart';

const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _kcal(double v) => fmtNum(v.roundToDouble());
String _g(double v) => fmtNum((v * 10).round() / 10);

class NutritionPage extends ConsumerStatefulWidget {
  const NutritionPage({super.key});

  @override
  ConsumerState<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends ConsumerState<NutritionPage> {
  DateTime _date = _today();

  void _show(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _moveDay(int by) => setState(() => _date = DateTime(_date.year, _date.month, _date.day + by));

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2024), lastDate: _today().add(const Duration(days: 7)));
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day));
  }

  Future<void> _add(String meal) async {
    final done = await showAddItemSheet(context, _date, meal);
    if (done != null && mounted) _show(done);
  }

  Future<void> _delete(DiaryItem i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Quitar «${i.name}»?'),
        content: Text('${_g(i.grams)} g · ${_kcal(i.kcal)} kcal'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(nutritionRepositoryProvider).deleteItem(i.id);
      ref.invalidate(diaryDayProvider(_date));
    } catch (e) {
      if (mounted) _show(apiMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dayAsync = ref.watch(diaryDayProvider(_date));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(mealForHour(DateTime.now().hour)),
        icon: const Icon(Icons.add),
        label: const Text('Apuntar'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  IconButton(tooltip: 'Día anterior', onPressed: () => _moveDay(-1), icon: const Icon(Icons.chevron_left)),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_date == _today() ? 'Hoy, ${shortDate(_date)}' : '${_weekdays[_date.weekday - 1]} ${shortDate(_date)}'),
                    ),
                  ),
                  IconButton(tooltip: 'Día siguiente', onPressed: () => _moveDay(1), icon: const Icon(Icons.chevron_right)),
                ]),
                const SizedBox(height: 8),
                ...dayAsync.when(
                  loading: () => [const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))],
                  error: (e, _) => [
                    const SizedBox(height: 32),
                    Text(apiMessage(e), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Center(child: FilledButton.tonal(onPressed: () => ref.invalidate(diaryDayProvider(_date)), child: const Text('Reintentar'))),
                  ],
                  data: (day) => [
                    _Totals(day: day),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyFoodsPage())),
                        icon: const Icon(Icons.menu_book_outlined, size: 18),
                        label: const Text('Mis platos y alimentos'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final (key, label) in meals) ...[
                      _MealPanel(
                        label: label,
                        items: day.itemsOf(key),
                        kcal: day.kcalOf(key),
                        onAdd: () => _add(key),
                        onDelete: _delete,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text('Lo que apuntes aquí manda sobre las kcal y la proteína escritas a mano en Peso.',
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kcal y proteína frente a los objetivos, y carbohidratos y grasa.
class _Totals extends StatelessWidget {
  const _Totals({required this.day});
  final DiaryDay day;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final kcalLeft = day.kcalTarget - day.kcal;
    final protLeft = day.proteinTarget - day.protein;

    Widget bar(String title, String value, double done, double target, String note, {required bool bad}) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text(title, style: t.textTheme.labelLarge)),
              Text(value, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: target <= 0 ? 0 : (done / target).clamp(0, 1),
                minHeight: 8,
                color: bad ? cs.error : cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Text(note, style: t.textTheme.bodySmall?.copyWith(color: bad ? cs.error : cs.onSurfaceVariant)),
          ],
        );

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        bar('Calorías', '${_kcal(day.kcal)} / ${day.kcalTarget} kcal', day.kcal, day.kcalTarget.toDouble(),
            kcalLeft >= 0 ? 'Te quedan ${_kcal(kcalLeft)} kcal.' : 'Te pasas ${_kcal(-kcalLeft)} kcal del objetivo.',
            bad: kcalLeft < 0),
        const SizedBox(height: 14),
        bar('Proteína', '${_g(day.protein)} / ${day.proteinTarget} g', day.protein, day.proteinTarget.toDouble(),
            protLeft > 0 ? 'Faltan ${_g(protLeft)} g.' : 'Objetivo de proteína cumplido.',
            bad: false),
        const SizedBox(height: 12),
        Text('Carbohidratos ${_g(day.carbs)} g · Grasa ${_g(day.fat)} g',
            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _MealPanel extends StatelessWidget {
  const _MealPanel({required this.label, required this.items, required this.kcal, required this.onAdd, required this.onDelete});
  final String label;
  final List<DiaryItem> items;
  final double kcal;
  final VoidCallback onAdd;
  final ValueChanged<DiaryItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          if (items.isNotEmpty) Text('${_kcal(kcal)} kcal', style: t.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
          IconButton(tooltip: 'Añadir a ${label.toLowerCase()}', onPressed: onAdd, icon: const Icon(Icons.add)),
        ]),
        for (final i in items)
          Row(children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.name),
                  Text('${_g(i.grams)} g · ${_kcal(i.kcal)} kcal · ${_g(i.protein)} g prot.',
                      style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
            IconButton(
              tooltip: 'Quitar ${i.name}',
              visualDensity: VisualDensity.compact,
              onPressed: () => onDelete(i),
              icon: const Icon(Icons.close, size: 18),
            ),
          ]),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Nada apuntado.', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
      ]),
    );
  }
}
