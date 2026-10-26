import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/sync_controller.dart';
import '../../core/theme.dart';
import '../workout/exercise_card.dart' show shortDate;
import 'health_widgets.dart';
import 'metric_chart.dart';
import 'metrics.dart';

const _ranges = [(7, '7 días'), (30, '30 días'), (90, '90 días')];

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Serie de cada valor con lo que hay en local (pulsera y registros de Peso). Se actualiza sola.
final metricSeriesProvider = Provider<AsyncValue<Map<String, List<DayValue>>>>((ref) {
  final health = ref.watch(localRecordsProvider('health_day'));
  final body = ref.watch(localRecordsProvider('body_entry'));
  if (!health.hasValue || !body.hasValue) return const AsyncLoading();
  return AsyncData({for (final m in metrics) m.key: seriesOf(m, health.value!, body.value!)});
});

/// Pestaña Salud: un resumen por valor (último, media del periodo y gráfica pequeña), la conexión
/// con la pulsera y las actividades. Funciona sin servidor: lee de la base local.
class HealthPage extends ConsumerStatefulWidget {
  const HealthPage({super.key});

  @override
  ConsumerState<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends ConsumerState<HealthPage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final all = ref.watch(metricSeriesProvider).valueOrNull;
    final range = rangeEnding(_today(), _days);
    final anyData = all != null && all.values.any((s) => inRange(s, range).isNotEmpty);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const HealthPanel(),
              const SizedBox(height: 16),
              // Un solo filtro, arriba, para todo lo de abajo
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [for (final (d, label) in _ranges) ButtonSegment(value: d, label: Text(label))],
                  selected: {_days},
                  onSelectionChanged: (s) => setState(() => _days = s.first),
                ),
              ),
              const SizedBox(height: 12),
              if (all == null)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else ...[
                if (!anyData)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'No hay datos en estos días. Conecta tu pulsera desde el móvil o apunta tu peso en Peso.',
                      style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                LayoutBuilder(builder: (context, c) {
                  final columns = c.maxWidth >= 720 ? 3 : 2;
                  const gap = 10.0;
                  final w = (c.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(spacing: gap, runSpacing: gap, children: [
                    for (final m in metrics)
                      SizedBox(
                        width: w,
                        child: _MetricCard(
                          metric: m,
                          series: inRange(all[m.key]!, range),
                          range: range,
                          onOpen: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => MetricDetailPage(metric: m, initialDays: _days),
                          )),
                        ),
                      ),
                  ]);
                }),
              ],
              const SizedBox(height: 16),
              const ActivitiesPanel(),
            ]),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, required this.series, required this.range, required this.onOpen});
  final Metric metric;
  final List<DayValue> series;
  final ({DateTime from, DateTime to}) range;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final st = MetricStats.of(series);
    final last = st.last;
    return Semantics(
      button: true,
      label: last == null
          ? '${metric.label}: sin datos en estos días'
          : '${metric.label}: ${metric.withUnit(last.value)} ${whenText(last.date, range.to, shortDate)}; media ${metric.withUnit(st.avg!)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(metric.icon, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(child: Text(metric.label, style: t.textTheme.labelLarge, overflow: TextOverflow.ellipsis)),
              Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
            ]),
            const SizedBox(height: 6),
            if (last == null)
              Text('Sin datos', style: t.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant))
            else ...[
              Text.rich(TextSpan(children: [
                TextSpan(text: metric.format(last.value), style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                if (metric.unit.isNotEmpty) TextSpan(text: ' ${metric.unit}', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ])),
              Text('${whenText(last.date, range.to, shortDate)} · media ${metric.withUnit(st.avg!)}',
                  style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              MetricChart(metric: metric, points: series, from: range.from, to: range.to, compact: true),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Un valor en detalle: el último en grande, media, mínimo y máximo, la gráfica y la lista de días.
class MetricDetailPage extends ConsumerStatefulWidget {
  const MetricDetailPage({super.key, required this.metric, this.initialDays = 30});
  final Metric metric;
  final int initialDays;

  @override
  ConsumerState<MetricDetailPage> createState() => _MetricDetailPageState();
}

class _MetricDetailPageState extends ConsumerState<MetricDetailPage> {
  late int _days = widget.initialDays;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final m = widget.metric;
    final range = rangeEnding(_today(), _days);
    final series = inRange(ref.watch(metricSeriesProvider).valueOrNull?[m.key] ?? const [], range);
    final st = MetricStats.of(series);

    Widget stat(String label, double? v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            Text(v == null ? '—' : m.withUnit(v), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: Text(m.label)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [for (final (d, label) in _ranges) ButtonSegment(value: d, label: Text(label))],
                    selected: {_days},
                    onSelectionChanged: (s) => setState(() => _days = s.first),
                  ),
                ),
                const SizedBox(height: 16),
                if (st.last == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text('Sin datos en estos días.', textAlign: TextAlign.center, style: t.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                  )
                else ...[
                  Text(m.withUnit(st.last!.value), style: t.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text('Último dato: ${whenText(st.last!.date, range.to, shortDate)}', style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  Row(children: [stat('Media', st.avg), stat('Mínimo', st.min), stat('Máximo', st.max)]),
                  if (m.target != null) ...[
                    const SizedBox(height: 8),
                    Text('La franja marca tu objetivo de la guía: ${m.format(m.target!.lo)}–${m.withUnit(m.target!.hi)} al día.',
                        style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 16),
                  Panel(child: MetricChart(metric: m, points: series, from: range.from, to: range.to)),
                  const SizedBox(height: 16),
                  Text('Día a día', style: t.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  for (final p in series.reversed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(child: Text(whenText(p.date, range.to, shortDate))),
                        Text(m.withUnit(p.value), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                      ]),
                    ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
