import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import 'exercise_card.dart';
import 'models.dart';
import 'workout_repository.dart';

const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

class WorkoutPage extends ConsumerStatefulWidget {
  const WorkoutPage({super.key});

  @override
  ConsumerState<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends ConsumerState<WorkoutPage> {
  DateTime _date = _today();
  String? _dayKey; // null = el que toca por día de la semana
  String? _draftKey;
  Map<String, SlotDraft> _drafts = {};
  bool _saving = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    for (final d in _drafts.values) {
      d.dispose();
    }
    super.dispose();
  }

  void _ensureDrafts(DayPlan plan) {
    final key = '${isoDate(plan.date)}_${plan.dayKey}';
    if (_draftKey == key) return;
    for (final d in _drafts.values) {
      d.dispose();
    }
    _drafts = {for (final s in plan.slots) s.slotExerciseId: SlotDraft(s)};
    _draftKey = key;
    _message = plan.saved ? 'Ya tienes esta sesión guardada. Si cambias algo, vuelve a guardar.' : null;
    _messageIsError = false;
  }

  void _changeDay(String key) => setState(() {
        _dayKey = key;
        _draftKey = null;
      });

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: _today().add(const Duration(days: 30)),
    );
    if (d != null) {
      setState(() {
        _date = DateTime(d.year, d.month, d.day);
        _draftKey = null;
      });
    }
  }

  List<String> _optionsFor(SlotDraft d) {
    final takenSlots = _drafts.keys.toSet();
    final chosen = {for (final o in _drafts.values) if (o != d) o.exerciseId};
    return [
      d.info.slotExerciseId,
      ...d.info.alternatives.where((a) => !takenSlots.contains(a) && !chosen.contains(a)),
    ];
  }

  Future<void> _swap(SlotDraft d, String dayKey, Map<String, Exercise> exercises) async {
    final options = _optionsFor(d);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Hoy hago…', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final id in options)
            ListTile(
              title: Text(exercises[id]!.name + (id == d.info.slotExerciseId ? ' (original)' : '')),
              subtitle: Text(exercises[id]!.muscleGroup),
              trailing: id == d.exerciseId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, id),
            ),
        ]),
      ),
    );
    if (picked == null || picked == d.exerciseId || !mounted) return;
    setState(() {
      d.exerciseId = picked;
      d.loading = true;
    });
    try {
      final next = await ref.read(workoutRepositoryProvider).slot(_date, dayKey, d.info.slotExerciseId, picked);
      if (!mounted) return;
      setState(() {
        d.replaceInfo(next);
        d.loading = false;
        _message = 'Cambiado a ${exercises[picked]!.name}. Pulsa Guardar sesión al terminar.';
        _messageIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        d.loading = false;
        _message = apiMessage(e);
        _messageIsError = true;
      });
    }
  }

  Future<void> _save(String dayKey) async {
    final slots = <({String slot, String exercise, List<SetEntry> sets})>[];
    for (final d in _drafts.values) {
      final sets = <SetEntry>[];
      for (var i = 0; i < d.info.sets; i++) {
        final lt = d.load[i].text.trim().replaceAll(',', '.');
        final rt = d.reps[i].text.trim();
        if (lt.isEmpty && rt.isEmpty) continue;
        final load = lt.isEmpty ? null : double.tryParse(lt);
        final reps = rt.isEmpty ? null : int.tryParse(rt);
        if ((lt.isNotEmpty && (load == null || load < 0 || load > 500)) || (rt.isNotEmpty && (reps == null || reps < 0 || reps > 300))) {
          setState(() {
            _message = 'Hay algún número que no se entiende. Usa solo cifras, por ejemplo 62,5 y 8.';
            _messageIsError = true;
          });
          return;
        }
        sets.add(SetEntry(load, reps));
      }
      if (sets.isNotEmpty) slots.add((slot: d.info.slotExerciseId, exercise: d.exerciseId, sets: sets));
    }
    if (slots.isEmpty) {
      setState(() {
        _message = 'Apunta al menos una serie antes de guardar.';
        _messageIsError = true;
      });
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(workoutRepositoryProvider).save(_date, dayKey, slots);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Sesión guardada · ${_weekdays[_date.weekday - 1]} ${shortDate(_date)}';
        _messageIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = apiMessage(e);
        _messageIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(message: apiMessage(e), onRetry: () => ref.invalidate(catalogProvider)),
      data: (cat) {
        final day = _dayKey == null ? cat.dayFor(_date) : cat.days.firstWhere((d) => d.key == _dayKey);
        final planAsync = ref.watch(dayPlanProvider((date: _date, day: day.key)));
        return Column(children: [
          Expanded(
            child: planAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(message: apiMessage(e), onRetry: () => ref.invalidate(dayPlanProvider((date: _date, day: day.key)))),
              data: (plan) {
                _ensureDrafts(plan);
                return _content(context, cat, day);
              },
            ),
          ),
          _bottomBar(context, day.key),
        ]);
      },
    );
  }

  Widget _content(BuildContext context, Catalog cat, ProgramDay day) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final accent = dayColor(context, day.color);
    final dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final d in cat.days)
                  ChoiceChip(
                    selected: d.key == day.key,
                    onSelected: (_) => _changeDay(d.key),
                    avatar: CircleAvatar(backgroundColor: dayColor(context, d.color), radius: 6),
                    label: Text(d.weekday != null ? '${dayNames[d.weekday! - 1]} · ${d.name}' : d.name),
                  ),
              ]),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(day.name.toUpperCase(),
                        style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: accent, height: 1)),
                    const SizedBox(height: 4),
                    Text(day.focus, style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('${_weekdays[_date.weekday - 1]} ${shortDate(_date)}'),
                ),
              ]),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Antes de empezar: 3–5 min de movilidad, 3–5 min de elíptica o bici y activación de core. '
                    'Las series de calentamiento no se apuntan.',
                    style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final d in _drafts.values) ...[
                ExerciseCard(
                  draft: d,
                  exercises: cat.exercises,
                  onSwapPressed: _optionsFor(d).length > 1 && !d.loading ? () => _swap(d, day.key, cat.exercises) : null,
                ),
                const SizedBox(height: 12),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(BuildContext context, String dayKey) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            FilledButton(
              onPressed: _saving || _drafts.isEmpty ? null : () => _save(dayKey),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar sesión'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _message ?? 'Apunta kg y repeticiones de cada serie. Si una máquina está ocupada, pulsa Cambiar.',
                style: TextStyle(color: _messageIsError ? cs.error : cs.onSurfaceVariant, fontSize: 13),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Reintentar')),
          ]),
        ),
      );
}
