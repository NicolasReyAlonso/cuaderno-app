/// Valores biométricos por día para la pantalla Salud: qué se mide, cómo se escribe y sus series.
library;

import 'package:flutter/material.dart' show IconData, Icons;

import '../workout/exercise_card.dart' show fmtNum;

enum ChartKind { bars, line } // barras: cantidades del día (desde cero); línea: tendencias

typedef DayValue = ({DateTime date, double value});

String thousands(num n) => n.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// 425 min → «7 h 05».
String hoursMinutes(double minutes) {
  final m = minutes.round();
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
}

class Metric {
  final String key, label, unit;
  final IconData icon;
  final ChartKind kind;
  final String Function(double) format;
  final ({double lo, double hi})? target; // franja de referencia (la de la guía, en pasos)
  final bool fromBody; // sale de los registros de Peso, no de la pulsera
  final double axisUnit; // las marcas del eje van en múltiplos de esto (60: horas enteras en el sueño)
  final String Function(double)? axisFormat;
  const Metric(this.key, this.label, this.unit, this.icon, this.kind, this.format,
      {this.target, this.fromBody = false, this.axisUnit = 1, this.axisFormat});

  String axisText(double v) => (axisFormat ?? format)(v);

  /// Valor con su unidad: «8.950 pasos», «7 h 05», «58 ppm».
  String withUnit(double v) => unit.isEmpty ? format(v) : '${format(v)} $unit';
}

String _int(double v) => thousands(v);
String _one(double v) => fmtNum((v * 10).round() / 10);

final metrics = <Metric>[
  Metric('steps', 'Pasos', 'pasos', Icons.directions_walk, ChartKind.bars, _int, target: (lo: 7000, hi: 8000)),
  Metric('active_kcal', 'Kcal activas', 'kcal', Icons.local_fire_department_outlined, ChartKind.bars, _int),
  Metric('sleep_minutes', 'Sueño', '', Icons.bedtime_outlined, ChartKind.bars, hoursMinutes, axisUnit: 60, axisFormat: (v) => '${(v / 60).round()} h'),
  Metric('resting_hr', 'Pulso en reposo', 'ppm', Icons.favorite_border, ChartKind.line, _int),
  Metric('hrv_ms', 'Variabilidad (VFC)', 'ms', Icons.monitor_heart_outlined, ChartKind.line, _one),
  Metric('weight_kg', 'Peso', 'kg', Icons.monitor_weight_outlined, ChartKind.line, _one, fromBody: true),
];

/// Serie de un valor por día, por fecha ascendente. [healthDays] y [bodyEntries]: registros locales {AAAA-MM-DD: datos}.
List<DayValue> seriesOf(Metric m, Map<String, Map<String, dynamic>> healthDays, Map<String, Map<String, dynamic>> bodyEntries) {
  final source = m.fromBody ? bodyEntries : healthDays;
  final out = <DayValue>[
    for (final e in source.entries)
      if (e.value[m.key] is num) (date: DateTime.parse(e.key), value: (e.value[m.key] as num).toDouble()),
  ]..sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// Los [days] días que acaban en [today] (incluido): [from, to].
({DateTime from, DateTime to}) rangeEnding(DateTime today, int days) {
  final to = DateTime(today.year, today.month, today.day);
  return (from: DateTime(to.year, to.month, to.day - (days - 1)), to: to);
}

List<DayValue> inRange(List<DayValue> s, ({DateTime from, DateTime to}) r) =>
    [for (final p in s) if (!p.date.isBefore(r.from) && !p.date.isAfter(r.to)) p];

class MetricStats {
  final double? avg, min, max;
  final DayValue? last;
  final int days; // días con dato
  const MetricStats({this.avg, this.min, this.max, this.last, this.days = 0});

  factory MetricStats.of(List<DayValue> s) {
    if (s.isEmpty) return const MetricStats();
    final xs = [for (final p in s) p.value];
    return MetricStats(
      avg: xs.reduce((a, b) => a + b) / xs.length,
      min: xs.reduce((a, b) => a < b ? a : b),
      max: xs.reduce((a, b) => a > b ? a : b),
      last: s.last,
      days: s.length,
    );
  }
}

/// «hoy», «ayer» o «20 oct».
String whenText(DateTime d, DateTime today, String Function(DateTime) shortDate) {
  final a = DateTime.utc(d.year, d.month, d.day), b = DateTime.utc(today.year, today.month, today.day);
  final diff = b.difference(a).inDays;
  return switch (diff) { 0 => 'hoy', 1 => 'ayer', _ => shortDate(d) };
}
