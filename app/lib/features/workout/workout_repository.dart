import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import 'models.dart';

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class WorkoutRepository {
  WorkoutRepository(this._dio);
  final Dio _dio;

  Future<Catalog> catalog() async {
    final r = await _dio.get<Map<String, dynamic>>('/catalog');
    return Catalog.fromJson(r.data!);
  }

  Future<Today> today(DateTime date) async {
    final r = await _dio.get<Map<String, dynamic>>('/workouts/${isoDate(date)}/today');
    return Today.fromJson(r.data!);
  }

  Future<DayPlan> plan(DateTime date, String dayKey, int week) async {
    final r = await _dio.get<Map<String, dynamic>>('/workouts/${isoDate(date)}/$dayKey/plan', queryParameters: {'week': week});
    return DayPlan.fromJson(r.data!);
  }

  /// Historial y sugerencia de un hueco con otro ejercicio (al pulsar Cambiar).
  Future<PlannedSlot> slot(DateTime date, String dayKey, int week, String slotId, String exerciseId) async {
    final r = await _dio.get<Map<String, dynamic>>('/workouts/${isoDate(date)}/$dayKey/slots/$slotId',
        queryParameters: {'exercise_id': exerciseId, 'week': week});
    return PlannedSlot.fromJson(r.data!);
  }

  Future<void> save(DateTime date, String dayKey, int week, List<({String slot, String exercise, List<SetEntry> sets})> slots) async {
    await _dio.put<void>('/workouts/${isoDate(date)}/$dayKey', queryParameters: {'week': week}, data: {
      'slots': [
        for (final s in slots)
          {'slot_exercise_id': s.slot, 'exercise_id': s.exercise, 'sets': [for (final e in s.sets) e.toJson()]},
      ],
    });
  }
}

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) => WorkoutRepository(ref.watch(dioProvider)));

final catalogProvider = FutureProvider<Catalog>((ref) => ref.watch(workoutRepositoryProvider).catalog());

final todayProvider = FutureProvider.autoDispose.family<Today, DateTime>(
  (ref, date) => ref.watch(workoutRepositoryProvider).today(date),
);

final dayPlanProvider = FutureProvider.autoDispose.family<DayPlan, ({DateTime date, String day, int week})>(
  (ref, k) => ref.watch(workoutRepositoryProvider).plan(k.date, k.day, k.week),
);
