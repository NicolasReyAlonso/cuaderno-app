import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'health_models.dart';

/// Lectura de Health Connect (Android) y Salud / HealthKit (iPhone). Solo lectura.
class HealthReader {
  final _h = Health();
  bool _configured = false;

  /// En macOS y web no hay almacén de salud: allí solo se ve lo ya sincronizado desde el móvil.
  bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;
  String get storeName => isAndroid ? 'Health Connect' : 'Salud';

  // Cada tipo es un permiso que el usuario ve y que Google Play revisa: solo lo que se usa.
  List<HealthDataType> get _sampleTypes => isAndroid
      ? const [
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.SLEEP_SESSION,
          HealthDataType.RESTING_HEART_RATE,
          HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
          HealthDataType.WEIGHT,
        ]
      : const [
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.RESTING_HEART_RATE,
          HealthDataType.HEART_RATE_VARIABILITY_SDNN,
          HealthDataType.WEIGHT,
        ];

  // En Android, leer una actividad también lee su distancia y sus kcal totales
  List<HealthDataType> get _allTypes => [
        HealthDataType.STEPS,
        ..._sampleTypes,
        HealthDataType.WORKOUT,
        if (isAndroid) ...[HealthDataType.DISTANCE_DELTA, HealthDataType.TOTAL_CALORIES_BURNED],
      ];

  static String _kindOf(HealthDataType t) => switch (t) {
        HealthDataType.ACTIVE_ENERGY_BURNED => 'active_kcal',
        HealthDataType.SLEEP_SESSION || HealthDataType.SLEEP_ASLEEP => 'sleep',
        HealthDataType.RESTING_HEART_RATE => 'resting_hr',
        HealthDataType.HEART_RATE_VARIABILITY_RMSSD || HealthDataType.HEART_RATE_VARIABILITY_SDNN => 'hrv',
        _ => 'weight',
      };

  Future<void> _configure() async {
    if (!_configured) await _h.configure();
    _configured = true;
  }

  /// null si se puede usar; si no, qué falta, en una frase.
  Future<String?> problem() async {
    if (!supported) return 'Los datos de la pulsera se leen desde la app del móvil.';
    await _configure();
    if (!isAndroid) return null;
    return switch (await _h.getHealthConnectSdkStatus()) {
      HealthConnectSdkStatus.sdkAvailable => null,
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired => 'Actualiza Health Connect desde Google Play para seguir.',
      _ => 'Este móvil no tiene Health Connect. Instálalo desde Google Play para seguir.',
    };
  }

  Future<void> installHealthConnect() => _h.installHealthConnect();

  /// Pide permiso de lectura. En iPhone devuelve true aunque se nieguen tipos: Salud no lo dice.
  Future<bool> connect() async {
    await _configure();
    final types = _allTypes;
    return _h.requestAuthorization(types, permissions: [for (final _ in types) HealthDataAccess.READ]);
  }

  Future<void> disconnect() async {
    await _configure();
    if (isAndroid) await _h.revokePermissions(); // en iPhone se quita desde la app Salud
  }

  /// Lee los últimos [days] días (hoy incluido). Un tipo sin permiso se salta: no impide leer los demás.
  Future<({List<Map<String, dynamic>> days, List<Map<String, dynamic>> activities})> read({int days = 30}) async {
    await _configure();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(today.year, today.month, today.day - (days - 1));

    final steps = <DateTime, int>{};
    for (var d = first; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1)) {
      try {
        final end = DateTime(d.year, d.month, d.day + 1);
        final n = await _h.getTotalStepsInInterval(d, end.isAfter(now) ? now : end);
        if (n != null && n > 0) steps[d] = n;
      } catch (_) {
        break; // sin permiso de pasos
      }
    }

    final samples = <Sample>[];
    for (final type in _sampleTypes) {
      try {
        // El sueño de la primera noche empieza el día anterior
        final from = type == HealthDataType.SLEEP_SESSION || type == HealthDataType.SLEEP_ASLEEP ? first.subtract(const Duration(hours: 12)) : first;
        for (final p in await _h.getHealthDataFromTypes(types: [type], startTime: from, endTime: now)) {
          final v = p.value;
          if (v is NumericHealthValue) {
            samples.add(Sample(_kindOf(type), v.numericValue.toDouble(), p.dateFrom, p.dateTo, source: p.sourceName));
          }
        }
      } catch (_) {
        // sin permiso para este tipo o sin datos: seguimos con el resto
      }
    }

    final workouts = <WorkoutSample>[];
    try {
      for (final p in await _h.getHealthDataFromTypes(types: [HealthDataType.WORKOUT], startTime: first, endTime: now)) {
        final v = p.value;
        if (v is WorkoutHealthValue) {
          workouts.add(WorkoutSample(
            id: p.uuid,
            kind: v.workoutActivityType.name,
            from: p.dateFrom,
            to: p.dateTo,
            kcal: v.totalEnergyBurned?.toDouble(),
            distanceM: v.totalDistance?.toDouble(),
            source: p.sourceName,
          ));
        }
      }
    } catch (_) {
      // sin permiso de actividades
    }

    return (days: dailySummaries(first: first, last: today, steps: steps, samples: samples), activities: activityPayload(workouts));
  }
}
