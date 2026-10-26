import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/local/local_db.dart';
import '../../core/local/sync_controller.dart';
import '../body/body_repository.dart';
import '../workout/models.dart';
import '../workout/planner.dart' show PlanError;
import '../workout/workout_repository.dart';
import 'models.dart';

/// Ver y activar planes funciona sin conexión (base local). Crear, editar, duplicar y borrar
/// planes o ejercicios, por ahora, con conexión: tras cada cambio se espera a la sincronización
/// para que ya esté en local.
class ProgramsRepository {
  ProgramsRepository(this._dio, this._ref);
  final Dio _dio;
  final Ref _ref;

  /// Un plan tuyo (de la base local) o una plantilla (de los datos de consulta guardados).
  Future<PlanDraft> get(String id) async {
    final own = decodeData(await _ref.read(localDbProvider).record('program', id));
    if (own != null) return PlanDraft.fromJson({...own, 'id': id, 'mine': true});
    final refData = await _ref.read(referenceProvider.future);
    for (final t in refData?['templates'] as List? ?? const []) {
      if (t['id'] == id) return PlanDraft.fromJson({...t as Map<String, dynamic>, 'mine': false});
    }
    throw const PlanError('Ese plan ya no existe. Puede que lo borraras en otro dispositivo.');
  }

  /// Pasa a usar este plan; [startedOn] marca la semana 1. Es un cambio del perfil: va sin conexión.
  Future<void> activate(String id, DateTime startedOn) =>
      _ref.read(bodyRepositoryProvider).saveProfile({'program_id': id, 'program_started_on': isoDate(startedOn)});

  Future<void> _synced() => _ref.read(syncControllerProvider.notifier).syncNow();

  /// Crea el plan si no tiene id; si lo tiene, lo sustituye entero.
  Future<PlanDraft> save(PlanDraft plan) async {
    final r = plan.id == null
        ? await _dio.post<Map<String, dynamic>>('/programs', data: plan.toJson())
        : await _dio.put<Map<String, dynamic>>('/programs/${plan.id}', data: plan.toJson());
    await _synced();
    return PlanDraft.fromJson(r.data!);
  }

  Future<void> delete(String id) async {
    await _dio.delete<void>('/programs/$id');
    await _synced();
  }

  Future<PlanDraft> duplicate(String id) async {
    final r = await _dio.post<Map<String, dynamic>>('/programs/$id/duplicate');
    await _synced();
    return PlanDraft.fromJson(r.data!);
  }

  Future<Exercise> createExercise({required String name, required String muscleGroup, required String unit, required String loadMode, required bool isCompound}) async {
    final r = await _dio.post<Map<String, dynamic>>('/exercises', data: {
      'name': name.trim(),
      'muscle_group': muscleGroup.trim(),
      'unit': unit,
      'load_mode': loadMode,
      'is_compound': isCompound,
    });
    await _synced();
    return Exercise.fromJson(r.data!);
  }
}

final programsRepositoryProvider = Provider<ProgramsRepository>((ref) => ProgramsRepository(ref.watch(dioProvider), ref));

/// Tus planes primero y luego las plantillas, de la base local. Activo = el del perfil.
final programsProvider = Provider<AsyncValue<List<ProgramSummary>>>((ref) {
  final programs = ref.watch(localProgramsProvider);
  final profile = ref.watch(profileProvider);
  if (programs.hasError) return AsyncError(programs.error!, programs.stackTrace ?? StackTrace.current);
  if (!programs.hasValue || !profile.hasValue) return const AsyncLoading();
  final active = profile.value!.programId ?? defaultProgramId;
  final list = [
    for (final p in programs.value!)
      ProgramSummary(
        id: p.id,
        name: p.name,
        weeks: p.weeks,
        daysPerWeek: [for (var w = 1; w <= p.weeks; w++) p.days.where((d) => d.info.week == w).length].fold(0, (a, b) => a > b ? a : b),
        mine: p.mine,
        active: p.id == active,
      ),
  ]..sort((a, b) => a.mine != b.mine ? (a.mine ? -1 : 1) : a.name.compareTo(b.name));
  return AsyncData(list);
});
