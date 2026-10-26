import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/local/sync_controller.dart';
import '../../core/local/sync_engine.dart';
import '../body/body_repository.dart' show profileProvider;
import 'models.dart';
import 'planner.dart';

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Plan por defecto (app/seed.py del backend) si el perfil no tiene ninguno.
const defaultProgramId = 'definicion-5d';

/// Entreno lee y guarda en la base local; la sincronización se encarga del servidor.
class WorkoutRepository {
  WorkoutRepository(this._engine, this._planner, this._onChange);
  final SyncEngine _engine;
  final Planner Function() _planner;
  final void Function() _onChange;

  /// Historial y sugerencia de un hueco con otro ejercicio (al pulsar Cambiar).
  Future<PlannedSlot> slot(DateTime date, String dayKey, int week, String slotId, String exerciseId) async =>
      _planner().slot(date, dayKey, week, slotId, exerciseId);

  Future<void> save(DateTime date, String dayKey, int week, List<({String slot, String exercise, List<SetEntry> sets})> slots) async {
    final data = _planner().sessionData(date, dayKey, week, slots); // lanza PlanError con el mismo texto que el servidor
    await _engine.put('workout_session', '${isoDate(date)}/$dayKey', data);
    _onChange();
  }
}

/// Junta varios valores asíncronos: error si alguno falla, cargando si falta alguno.
AsyncValue<T> _combine<T>(List<AsyncValue<Object?>> parts, T Function() build) {
  for (final p in parts) {
    if (p.hasError) return AsyncError(p.error!, p.stackTrace ?? StackTrace.current);
  }
  if (parts.any((p) => !p.hasValue)) return const AsyncLoading();
  try {
    return AsyncData(build());
  } on PlanError catch (e, st) {
    return AsyncError(e, st);
  }
}

const _noCatalog = PlanError('Conecta una vez con el servidor para descargar el catálogo de ejercicios y tu plan.');

/// Datos de consulta guardados (GET /sync/reference): ejercicios, alternativas y plantillas del catálogo.
final referenceProvider = StreamProvider<Map<String, dynamic>?>((ref) =>
    ref.watch(localDbProvider).watchMeta('ref_data').map((raw) => raw == null ? null : jsonDecode(raw) as Map<String, dynamic>));

/// URL firmadas de las fotos y vídeos de tus ejercicios. Sin conexión: ninguna (se ve un icono).
final mediaUrlsProvider = FutureProvider<Map<String, String>>((ref) async {
  final own = await ref.watch(localRecordsProvider('exercise').future);
  final ids = [for (final e in own.values) for (final m in e['media'] as List? ?? const []) (m as Map)['id'] as String];
  if (ids.isEmpty) return const {};
  try {
    final r = await ref.read(dioProvider).post<Map<String, dynamic>>('/media/urls', data: {'ids': ids});
    return r.data!.map((k, v) => MapEntry(k, v as String));
  } catch (_) {
    return const {};
  }
});

final exercisesProvider = Provider<AsyncValue<Map<String, Exercise>>>((ref) {
  final refData = ref.watch(referenceProvider);
  final own = ref.watch(localRecordsProvider('exercise'));
  final urls = ref.watch(mediaUrlsProvider).valueOrNull ?? const <String, String>{};
  return _combine([refData, own], () {
    final catalog = refData.value?['exercises'] as List?;
    if (catalog == null) throw _noCatalog;
    return {
      for (final e in catalog) e['id'] as String: Exercise.fromSync(e['id'] as String, e as Map<String, dynamic>, mine: false),
      for (final e in own.value!.entries) e.key: Exercise.fromSync(e.key, e.value, mine: true, urls: urls),
    };
  });
});

/// Tus planes y las plantillas.
final localProgramsProvider = Provider<AsyncValue<List<LocalProgram>>>((ref) {
  final refData = ref.watch(referenceProvider);
  final own = ref.watch(localRecordsProvider('program'));
  return _combine([refData, own], () => [
        for (final e in own.value!.entries) LocalProgram.fromJson(e.key, e.value, mine: true),
        for (final t in refData.value?['templates'] as List? ?? const []) LocalProgram.fromJson(t['id'] as String, t as Map<String, dynamic>, mine: false),
      ]);
});

final _sessionsProvider = Provider<AsyncValue<List<LocalSession>>>((ref) =>
    ref.watch(localRecordsProvider('workout_session')).whenData((rows) => [for (final s in rows.values) LocalSession.fromJson(s)]));

final plannerProvider = Provider<AsyncValue<Planner>>((ref) {
  final exercises = ref.watch(exercisesProvider);
  final programs = ref.watch(localProgramsProvider);
  final sessions = ref.watch(_sessionsProvider);
  final profile = ref.watch(profileProvider);
  final refData = ref.watch(referenceProvider);
  return _combine([exercises, programs, sessions, profile, refData], () {
    final wanted = profile.value!.programId ?? defaultProgramId;
    final all = programs.value!;
    final program = all.where((p) => p.id == wanted).firstOrNull ?? all.where((p) => p.id == defaultProgramId).firstOrNull;
    if (program == null) throw _noCatalog;
    final alts = (refData.value?['alternatives'] as Map<String, dynamic>? ?? const {})
        .map((k, v) => MapEntry(k, [for (final a in v as List) a as String]));
    return Planner(program: program, exercises: exercises.value!, alternatives: alts, sessions: sessions.value!, startedOn: profile.value!.programStartedOn);
  });
});

/// Ejercicios visibles y el plan activo (con los días de todas sus semanas).
final catalogProvider = Provider<AsyncValue<Catalog>>((ref) => ref
    .watch(plannerProvider)
    .whenData((p) => Catalog(p.exercises, p.program.name, p.program.weeks, [for (final d in p.program.days) d.info])));

final todayProvider = Provider.family<AsyncValue<Today>, DateTime>((ref, date) => ref.watch(plannerProvider).whenData((p) => p.today(date)));

final dayPlanProvider = Provider.family<AsyncValue<DayPlan>, ({DateTime date, String day, int week})>(
  (ref, k) => _combine([ref.watch(plannerProvider)], () => ref.read(plannerProvider).value!.plan(k.date, k.day, week: k.week)),
);

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) => WorkoutRepository(
      ref.watch(syncEngineProvider),
      () => ref.read(plannerProvider).value ?? (throw _noCatalog),
      () => ref.read(syncControllerProvider.notifier).changed(),
    ));
