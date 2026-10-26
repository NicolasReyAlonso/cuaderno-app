import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_db.dart';
import '../../core/local/sync_api.dart' show uuidV4;
import '../../core/local/sync_controller.dart';
import '../../core/local/sync_engine.dart';
import '../body/body_repository.dart';
import '../workout/models.dart';
import '../workout/planner.dart' show PlanError;
import '../workout/workout_repository.dart';
import 'models.dart';

/// Planes y ejercicios propios: todo en la base local, también sin conexión.
/// La sincronización los envía en orden (el ejercicio antes que el plan que lo usa).
class ProgramsRepository {
  ProgramsRepository(this._ref);
  final Ref _ref;

  SyncEngine get _engine => _ref.read(syncEngineProvider);
  void _changed() => _ref.read(syncControllerProvider.notifier).changed();
  static String _newId() => 'u:${uuidV4().replaceAll('-', '').substring(0, 12)}';

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

  /// Pasa a usar este plan; [startedOn] marca la semana 1. Es un cambio del perfil.
  Future<void> activate(String id, DateTime startedOn) =>
      _ref.read(bodyRepositoryProvider).saveProfile({'program_id': id, 'program_started_on': isoDate(startedOn)});

  /// Crea el plan si no tiene id; si lo tiene, lo sustituye entero.
  Future<PlanDraft> save(PlanDraft plan) async {
    final exercises = _ref.read(exercisesProvider).valueOrNull ?? const {};
    final missing = {for (final d in plan.days) for (final s in d.slots) s.exerciseId}.where((e) => !exercises.containsKey(e));
    if (missing.isNotEmpty) throw PlanError('El ejercicio «${missing.first}» no existe. Elige uno del catálogo o crea uno propio.');
    final id = plan.id ?? _newId();
    final data = programData(plan);
    await _engine.put('program', id, data);
    _changed();
    return PlanDraft.fromJson({...data, 'id': id, 'mine': true});
  }

  Future<void> delete(String id) async {
    final active = _ref.read(profileProvider).valueOrNull?.programId;
    if (active == id) throw const PlanError('Es tu plan activo. Activa otro antes de borrarlo.');
    await _engine.remove('program', id);
    _changed();
  }

  /// Copia como tuya, con el nombre «… (copia)».
  Future<PlanDraft> duplicate(String id) async {
    final src = await get(id);
    final name = '${src.name} (copia)';
    final copy = PlanDraft(name: name.length > 120 ? name.substring(0, 120) : name, weeks: src.weeks, days: [for (final d in src.days) d.copyTo(d.week)]);
    return save(copy);
  }

  Future<Exercise> createExercise({required String name, required String muscleGroup, required String unit, required String loadMode, required bool isCompound}) async {
    final id = _newId();
    final data = {
      'name': name.trim(),
      'muscle_group': muscleGroup.trim(),
      'cue': '',
      'unit': unit,
      'load_mode': loadMode,
      'is_compound': isCompound,
      'default_rep_min': null,
      'default_rep_max': null,
      'figure': genericFigure, // la misma que pone el servidor
      'media': <Map<String, dynamic>>[],
    };
    await _engine.put('exercise', id, data);
    _changed();
    return Exercise.fromSync(id, data, mine: true);
  }
}

/// JSON del registro «program»: días ordenados por semana y su posición dentro de cada una
/// (como fill_program del backend).
Map<String, dynamic> programData(PlanDraft plan) {
  final json = plan.toJson();
  final days = [...(json['days'] as List).cast<Map<String, dynamic>>()]..sort((a, b) => (a['week'] as int).compareTo(b['week'] as int));
  final pos = <int, int>{};
  return {
    ...json,
    'days': [
      for (final d in days) {...d, 'position': pos.update(d['week'] as int, (v) => v + 1, ifAbsent: () => 0)},
    ],
  };
}

/// Figura de los ejercicios propios: de pie, de frente, brazos de abajo a la altura de los hombros.
/// Copia de GENERIC_FIGURE (backend/app/routers/catalog.py).
const genericFigure = <String, dynamic>{
  'front': true,
  'a': {'hip': [100, 84], 't': 90, 'hand': [86, 90], 'hand2': [114, 90], 'foot': [93, 156], 'foot2': [107, 156]},
  'b': {'hip': [100, 84], 't': 90, 'hand': [44, 42], 'hand2': [156, 42], 'foot': [93, 156], 'foot2': [107, 156]},
  'eb': 1,
  'eb2': -1,
  'kb': -1,
  'kb2': 1,
};

final programsRepositoryProvider = Provider<ProgramsRepository>((ref) => ProgramsRepository(ref));

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
