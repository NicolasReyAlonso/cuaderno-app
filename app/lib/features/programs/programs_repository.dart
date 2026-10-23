import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../workout/models.dart';
import '../workout/workout_repository.dart';
import 'models.dart';

class ProgramsRepository {
  ProgramsRepository(this._dio);
  final Dio _dio;

  Future<List<ProgramSummary>> list() async {
    final r = await _dio.get<List<dynamic>>('/programs');
    return [for (final p in r.data!) ProgramSummary.fromJson(p as Map<String, dynamic>)];
  }

  Future<PlanDraft> get(String id) async {
    final r = await _dio.get<Map<String, dynamic>>('/programs/$id');
    return PlanDraft.fromJson(r.data!);
  }

  /// Crea el plan si no tiene id; si lo tiene, lo sustituye entero.
  Future<PlanDraft> save(PlanDraft plan) async {
    final r = plan.id == null
        ? await _dio.post<Map<String, dynamic>>('/programs', data: plan.toJson())
        : await _dio.put<Map<String, dynamic>>('/programs/${plan.id}', data: plan.toJson());
    return PlanDraft.fromJson(r.data!);
  }

  Future<void> delete(String id) => _dio.delete<void>('/programs/$id');

  Future<PlanDraft> duplicate(String id) async {
    final r = await _dio.post<Map<String, dynamic>>('/programs/$id/duplicate');
    return PlanDraft.fromJson(r.data!);
  }

  Future<void> activate(String id, DateTime startedOn) =>
      _dio.post<void>('/programs/$id/activate', data: {'started_on': isoDate(startedOn)});

  Future<Exercise> createExercise({required String name, required String muscleGroup, required String unit, required String loadMode, required bool isCompound}) async {
    final r = await _dio.post<Map<String, dynamic>>('/exercises', data: {
      'name': name.trim(),
      'muscle_group': muscleGroup.trim(),
      'unit': unit,
      'load_mode': loadMode,
      'is_compound': isCompound,
    });
    return Exercise.fromJson(r.data!);
  }
}

final programsRepositoryProvider = Provider<ProgramsRepository>((ref) => ProgramsRepository(ref.watch(dioProvider)));

final programsProvider = FutureProvider.autoDispose<List<ProgramSummary>>((ref) => ref.watch(programsRepositoryProvider).list());

/// Tras activar o editar un plan: la lista, el catálogo (plan activo) y el Entreno cambian.
void refreshAfterPlanChange(WidgetRef ref) {
  ref.invalidate(programsProvider);
  ref.invalidate(catalogProvider);
  ref.invalidate(todayProvider);
  ref.invalidate(dayPlanProvider);
}
