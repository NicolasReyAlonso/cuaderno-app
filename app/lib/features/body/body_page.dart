import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../workout/exercise_card.dart' show fmtNum, shortDate;
import '../health/health_widgets.dart';
import '../../core/local/sync_controller.dart';
import 'body_repository.dart';
import 'models.dart';
import 'profile_sheet.dart';
import 'weight_chart.dart';

const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _kg(double v) => fmtNum((v * 10).round() / 10);
String _signed(double v, String unit) => '${v > 0 ? '+' : v < 0 ? '−' : ''}${fmtNum(((v.abs()) * 10).round() / 10)} $unit';

class BodyPage extends ConsumerStatefulWidget {
  const BodyPage({super.key});

  @override
  ConsumerState<BodyPage> createState() => _BodyPageState();
}

class _BodyPageState extends ConsumerState<BodyPage> {
  final _scroll = ScrollController();
  DateTime _date = _today();
  int _rangeDays = 30; // 0 = todo
  bool _allEntries = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _editDay(DateTime d) {
    setState(() => _date = d);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    still ? _scroll.jumpTo(0) : _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _openProfile() async {
    final profile = ref.read(profileProvider).valueOrNull ?? Profile.fromJson(defaultProfileData);
    final saved = await showProfileSheet(context, profile);
    if (saved == true && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Punto de partida y objetivos guardados.')));
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(bodySummaryProvider);
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: summary.when(
              loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Column(children: [
                const SizedBox(height: 32),
                Text(apiMessage(e), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonal(onPressed: () => ref.invalidate(localRecordsProvider), child: const Text('Reintentar')),
              ]),
              data: (s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _EntryPanel(
                  key: ValueKey((_date, s.entryOn(_date) == null)),
                  date: _date,
                  entry: s.entryOn(_date),
                  onDate: (d) => setState(() => _date = d),
                ),
                const SizedBox(height: 16),
                _Stats(s: s, onProfile: _openProfile),
                const SizedBox(height: 16),
                const HealthPanel(),
                const SizedBox(height: 16),
                _chartPanel(context, s),
                const SizedBox(height: 16),
                if (s.weeks.isNotEmpty) ...[_WeeksPanel(weeks: s.weeks), const SizedBox(height: 16)],
                const ActivitiesPanel(),
                _entriesPanel(context, s),
              ]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chartPanel(BuildContext context, BodySummary s) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final all = weightSeries(s.entries);
    final from = _rangeDays == 0 || all.isEmpty ? null : daysBefore(all.last.date, _rangeDays - 1);
    final pts = [for (final p in all) if (from == null || !p.date.isBefore(from)) p];
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Evolución del peso', style: t.textTheme.titleMedium),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: 30, label: Text('30 días')), ButtonSegment(value: 90, label: Text('90 días')), ButtonSegment(value: 0, label: Text('Todo'))],
            selected: {_rangeDays},
            onSelectionChanged: (v) => setState(() => _rangeDays = v.first),
          ),
        ]),
        const SizedBox(height: 8),
        // Leyenda: dos series, la forma de cada marca junto a su nombre
        Wrap(spacing: 16, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 14, height: 2, color: cs.primary),
            const SizedBox(width: 6),
            Text('Media de 7 días', style: t.textTheme.labelMedium),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.45), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('Peso de cada día', style: t.textTheme.labelMedium),
          ]),
        ]),
        const SizedBox(height: 12),
        if (pts.length < 2)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              all.length < 2 ? 'Apunta tu peso dos días o más para ver la gráfica.' : 'En este rango hay menos de dos pesos. Elige un rango más largo.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          )
        else
          WeightChart(points: pts),
      ]),
    );
  }

  Widget _entriesPanel(BuildContext context, BodySummary s) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final rows = s.entries.reversed.toList();
    final shown = _allEntries ? rows : rows.take(14).toList();
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Registros', style: t.textTheme.titleMedium),
        Text('Toca un día para corregirlo.', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Aún no hay registros.', style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
        for (final e in shown)
          InkWell(
            onTap: () => _editDay(e.date),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(width: 90, child: Text('${_weekdays[e.date.weekday - 1].substring(0, 3)} ${shortDate(e.date)}')),
                Expanded(
                  child: Text(
                    [
                      if (e.weightKg != null) '${fmtNum(e.weightKg!)} kg${e.weightFromHealth ? ' (báscula)' : ''}',
                      if (e.waistCm != null) 'cintura ${fmtNum(e.waistCm!)} cm',
                      if (e.kcal != null) '${fmtNum(e.kcal!)} kcal${e.fromDiary ? ' (diario)' : ''}',
                      if (e.proteinG != null) '${fmtNum(e.proteinG!)} g prot.',
                    ].join(' · '),
                    style: t.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ]),
            ),
          ),
        if (rows.length > 14)
          TextButton(
            onPressed: () => setState(() => _allEntries = !_allEntries),
            child: Text(_allEntries ? 'Ver solo los últimos 14' : 'Ver los ${rows.length}'),
          ),
      ]),
    );
  }
}

/// Peso, cintura y, si ese día no hay diario de comidas, kcal y proteína a mano.
class _EntryPanel extends ConsumerStatefulWidget {
  const _EntryPanel({super.key, required this.date, required this.entry, required this.onDate});
  final DateTime date;
  final BodyEntry? entry;
  final ValueChanged<DateTime> onDate;

  @override
  ConsumerState<_EntryPanel> createState() => _EntryPanelState();
}

class _EntryPanelState extends ConsumerState<_EntryPanel> {
  late final _weight = TextEditingController(text: _fmt(widget.entry?.weightKg));
  late final _waist = TextEditingController(text: _fmt(widget.entry?.waistCm));
  late final _kcal = TextEditingController(text: widget.entry?.fromDiary ?? false ? '' : _fmt(widget.entry?.kcal));
  late final _protein = TextEditingController(text: widget.entry?.fromDiary ?? false ? '' : _fmt(widget.entry?.proteinG));
  bool _saving = false;
  String? _message;
  bool _isError = false;

  static String _fmt(double? v) => v == null ? '' : fmtNum(v);

  bool get _fromDiary => widget.entry?.fromDiary ?? false;
  bool get _hasOwnData => widget.entry != null && (widget.entry!.weightKg != null || widget.entry!.waistCm != null || !_fromDiary);

  @override
  void dispose() {
    for (final c in [_weight, _waist, _kcal, _protein]) {
      c.dispose();
    }
    super.dispose();
  }

  void _say(String m, {bool error = false}) => setState(() {
        _message = m;
        _isError = error;
      });

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: widget.date, firstDate: DateTime(2024), lastDate: _today());
    if (d != null) widget.onDate(DateTime(d.year, d.month, d.day));
  }

  Future<void> _save() async {
    final input = entryInput(weight: _weight.text, waist: _waist.text, kcal: _kcal.text, protein: _protein.text, fromDiary: _fromDiary);
    if (input.error != null) return _say(input.error!, error: true);
    setState(() => _saving = true);
    try {
      await ref.read(bodyRepositoryProvider).saveEntry(widget.date, input.json!);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Guardado: ${shortDate(widget.date)}.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _say(apiMessage(e), error: true);
      }
    }
  }

  Future<void> _delete() async {
    try {
      await ref.read(bodyRepositoryProvider).deleteEntry(widget.date);
    } catch (e) {
      if (mounted) _say(apiMessage(e), error: true);
    }
  }

  Widget _num(TextEditingController c, String label, String suffix, {bool decimal = true}) => SizedBox(
        width: 130,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          decoration: InputDecoration(labelText: label, suffixText: suffix),
          onSubmitted: (_) => _saving ? null : _save(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final d = widget.date;
    final e = widget.entry;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(tooltip: 'Día anterior', onPressed: () => widget.onDate(DateTime(d.year, d.month, d.day - 1)), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: TextButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(d == _today() ? 'Hoy, ${shortDate(d)}' : '${_weekdays[d.weekday - 1]} ${shortDate(d)}'),
            ),
          ),
          IconButton(
            tooltip: 'Día siguiente',
            onPressed: d == _today() ? null : () => widget.onDate(DateTime(d.year, d.month, d.day + 1)),
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 12, children: [
          _num(_weight, 'Peso', 'kg'),
          _num(_waist, 'Cintura', 'cm'),
          if (!_fromDiary) ...[
            _num(_kcal, 'Calorías', 'kcal', decimal: false),
            _num(_protein, 'Proteína', 'g', decimal: false),
          ],
        ]),
        const SizedBox(height: 6),
        Text(
          _fromDiary
              ? 'Calorías y proteína de este día salen del diario: ${fmtNum(e!.kcal ?? 0)} kcal · ${fmtNum(e.proteinG ?? 0)} g.'
              : 'Calorías y proteína solo si ese día no usas el diario de Comidas.',
          style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Row(children: [
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar'),
          ),
          if (_hasOwnData) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: _saving ? null : _delete, child: const Text('Borrar el día')),
          ],
          const SizedBox(width: 12),
          if (_message != null)
            Expanded(child: Text(_message!, style: TextStyle(color: _isError ? cs.error : cs.onSurfaceVariant, fontSize: 13))),
        ]),
      ]),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.s, required this.onProfile});
  final BodySummary s;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    Widget tile(String label, String value, String? note) => SizedBox(
          width: 180,
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: t.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(value, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              if (note != null) Text(note, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        );
    final cur = s.currentWeight;
    String? left(double? goal) => goal == null || cur == null ? null : cur > goal ? 'te faltan ${_kg(cur - goal)} kg' : 'conseguido';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        tile('Peso (media 7 días)', cur == null ? '—' : '${_kg(cur)} kg',
            s.currentWeightDate == null ? 'Apunta tu peso' : 'al ${shortDate(s.currentWeightDate!)}'),
        if (s.bodyFatEst != null) tile('Grasa estimada', '${fmtNum(s.bodyFatEst!)} %', s.leanMass == null ? null : 'masa magra ${_kg(s.leanMass!)} kg'),
        if (s.goal25Weight != null) tile('Peso para 25 %', '${_kg(s.goal25Weight!)} kg', left(s.goal25Weight)),
        if (s.goal20Weight != null) tile('Peso para 20 %', '${_kg(s.goal20Weight!)} kg', left(s.goal20Weight)),
      ]),
      if (s.leanMass == null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Pon tu peso y tu grasa del inicio para ver la grasa estimada y el peso de cada objetivo.',
              style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(onPressed: onProfile, icon: const Icon(Icons.tune, size: 18), label: const Text('Punto de partida y objetivos')),
      ),
    ]);
  }
}

class _WeeksPanel extends StatelessWidget {
  const _WeeksPanel({required this.weeks});
  final List<BodyWeek> weeks;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final muted = t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Semana a semana', style: t.textTheme.titleMedium),
        Text('En ritmo: bajar entre 0,4 % y 1,1 % del peso a la semana.', style: muted),
        const SizedBox(height: 8),
        for (final w in weeks.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Semana del ${shortDate(w.monday)}', style: t.textTheme.labelLarge),
                  Text(
                    [
                      if (w.avgWeight != null) '${_kg(w.avgWeight!)} kg (${w.nWeights} ${w.nWeights == 1 ? 'pesaje' : 'pesajes'})',
                      if (w.deltaKg != null) '${_signed(w.deltaKg!, 'kg')} · ${_signed(w.deltaPct!, '%')}',
                      if (w.avgKcal != null) '${fmtNum(w.avgKcal!.roundToDouble())} kcal/día',
                      if (w.avgProtein != null) '${fmtNum(w.avgProtein!.roundToDouble())} g prot./día',
                      if (w.waistCm != null) 'cintura ${fmtNum(w.waistCm!)} cm',
                    ].join(' · '),
                    style: muted?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  if (bandLine(w).isNotEmpty)
                    Text(bandLine(w), style: muted?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
              ),
              if (w.pace != null) _PaceChip(pace: w.pace!),
            ]),
          ),
      ]),
    );
  }
}

class _PaceChip extends StatelessWidget {
  const _PaceChip({required this.pace});
  final String pace;

  @override
  Widget build(BuildContext context) {
    final s = paceStyle(context, pace);
    return DecoratedBox(
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(999)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(s.icon, size: 14, color: s.fg),
          const SizedBox(width: 4),
          Text(paceLabels[pace] ?? pace, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: s.fg, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Medias de la pulsera en la semana: «8.950 pasos/día · 420 kcal activas · sueño 7 h 05 · pulso 58».
String bandLine(BodyWeek w) => [
      if (w.avgSteps != null) '${_thousands(w.avgSteps!.round())} pasos/día',
      if (w.avgActiveKcal != null) '${w.avgActiveKcal!.round()} kcal activas',
      if (w.avgSleepMinutes != null) 'sueño ${sleepText(w.avgSleepMinutes!)}',
      if (w.avgRestingHr != null) 'pulso ${w.avgRestingHr!.round()}',
    ].join(' · ');

/// 425 min → «7 h 05».
String sleepText(double minutes) {
  final m = minutes.round();
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
}

String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
