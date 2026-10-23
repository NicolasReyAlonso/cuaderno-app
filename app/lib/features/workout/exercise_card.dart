import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../figures/figure_view.dart';
import 'models.dart';

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String fmtNum(double v) {
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(v * 10 == (v * 10).roundToDouble() ? 1 : 2);
  return s.replaceAll('.', ',');
}

/// Estado editable de un hueco del día.
class SlotDraft {
  SlotDraft(this.info) : exerciseId = info.exerciseId {
    _resetControllers();
  }

  PlannedSlot info;
  String exerciseId;
  bool loading = false;
  late List<TextEditingController> load;
  late List<TextEditingController> reps;

  void _resetControllers() {
    load = List.generate(info.sets, (i) => TextEditingController(text: i < info.logged.length && info.logged[i].load != null ? fmtNum(info.logged[i].load!) : ''));
    reps = List.generate(info.sets, (i) => TextEditingController(text: i < info.logged.length ? (info.logged[i].reps?.toString() ?? '') : ''));
  }

  void replaceInfo(PlannedSlot next) {
    dispose();
    info = next;
    exerciseId = next.exerciseId;
    _resetControllers();
  }

  /// Se liberan tras el siguiente frame: los TextField aún pueden tenerlos
  /// enganchados hasta que se reconstruyen con los nuevos.
  void dispose() {
    final old = [...load, ...reps];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }
}

class ExerciseCard extends StatelessWidget {
  const ExerciseCard({super.key, required this.draft, required this.exercises, required this.onSwapPressed});

  final SlotDraft draft;
  final Map<String, Exercise> exercises;
  final VoidCallback? onSwapPressed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final ex = exercises[draft.exerciseId]!;
    final original = exercises[draft.info.slotExerciseId]!;
    final swapped = draft.exerciseId != draft.info.slotExerciseId;
    final i = draft.info;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(ex.name, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Text(ex.muscleGroup.toUpperCase(), style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.6)),
        ]),
        if (swapped)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('En lugar de: ${original.name}', style: t.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 4),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          Text('${i.sets} × ${i.repMin}–${i.repMax}${ex.isSeconds ? ' s' : ''} · descanso ${i.rest}',
              style: t.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', color: cs.onSurfaceVariant)),
          if (onSwapPressed != null)
            OutlinedButton.icon(
              onPressed: onSwapPressed,
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: const Text('Cambiar'),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
            ),
        ]),
        const SizedBox(height: 4),
        Text(ex.cue, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        if (draft.loading) const LinearProgressIndicator() else _LastAndHint(info: i, ex: ex),
        const SizedBox(height: 8),
        _SetsTable(draft: draft, ex: ex),
      ],
    );

    return Panel(
      highlight: swapped ? cs.primary : null,
      child: LayoutBuilder(builder: (context, c) {
        final figure = DecoratedBox(
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: AnimatedFigure(key: ValueKey(ex.id), spec: ex.figure)),
        );
        if (c.maxWidth < 420) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: SizedBox(width: 220, child: figure)),
            const SizedBox(height: 10),
            details,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: c.maxWidth < 560 ? 120 : 150, child: figure),
          const SizedBox(width: 14),
          Expanded(child: details),
        ]);
      }),
    );
  }
}

class _LastAndHint extends StatelessWidget {
  const _LastAndHint({required this.info, required this.ex});
  final PlannedSlot info;
  final Exercise ex;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final children = <Widget>[];
    if (info.lastDate != null && info.lastSets.isNotEmpty) {
      final loads = info.lastSets.map((s) => s.load == null ? '–' : fmtNum(s.load!)).toList();
      final sameLoad = loads.every((l) => l == loads.first);
      final body = sameLoad
          ? '${loads.first} kg × ${info.lastSets.map((s) => s.reps?.toString() ?? '–').join(' · ')}'
          : info.lastSets.map((s) => '${s.load == null ? '–' : fmtNum(s.load!)}×${s.reps ?? '–'}').join(' · ');
      children.add(Text('${shortDate(info.lastDate!)}: $body${ex.isSeconds ? ' s' : ''}',
          style: t.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')));
    }
    if (info.hint != null) {
      final c = hintColors(context, info.hint!.kind);
      children.add(DecoratedBox(
        decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(999)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(info.hint!.text, style: t.textTheme.labelSmall?.copyWith(color: c.fg, fontWeight: FontWeight.w600)),
        ),
      ));
    }
    return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: children);
  }
}

class _SetsTable extends StatelessWidget {
  const _SetsTable({required this.draft, required this.ex});
  final SlotDraft draft;
  final Exercise ex;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final last = draft.info.lastSets;
    String hintLoad(int i) {
      if (last.isEmpty) return ex.isExtraLoad ? '0' : 'kg';
      final s = i < last.length ? last[i] : last.last;
      return s.load == null ? '' : fmtNum(s.load!);
    }

    String hintReps(int i) {
      if (last.isEmpty) return '${draft.info.repMax}';
      final s = i < last.length ? last[i] : last.last;
      return s.reps?.toString() ?? '';
    }

    final labelStyle = t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 26, bottom: 4),
        child: Text('${ex.isExtraLoad ? 'KG EXTRA · 0 SIN LASTRE' : 'KG'}   ×   ${ex.isSeconds ? 'SEGUNDOS' : 'REPS'}', style: labelStyle),
      ),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (var i = 0; i < draft.info.sets; i++)
          SizedBox(
            width: 168,
            child: Row(children: [
              SizedBox(width: 18, child: Text('${i + 1}', style: labelStyle, textAlign: TextAlign.center)),
              const SizedBox(width: 4),
              Expanded(child: _num(draft.load[i], hintLoad(i), '${ex.name}, serie ${i + 1}, kilos', decimal: true)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('×', style: labelStyle)),
              Expanded(child: _num(draft.reps[i], hintReps(i), '${ex.name}, serie ${i + 1}, ${ex.isSeconds ? 'segundos' : 'repeticiones'}')),
            ]),
          ),
      ]),
    ]);
  }

  Widget _num(TextEditingController c, String hint, String label, {bool decimal = false}) => Semantics(
        label: label,
        child: TextField(
          controller: c,
          textAlign: TextAlign.end,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          decoration: InputDecoration(hintText: hint, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      );
}
