import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_db.dart';
import '../../core/local/sync_controller.dart';
import '../../core/local/sync_engine.dart';
import '../nutrition/nutrition_repository.dart' show diaryTotalsProvider;
import '../workout/workout_repository.dart' show isoDate;
import 'models.dart';

/// Peso y perfil leen y escriben en la base local; la sincronización se encarga del servidor.
class BodyRepository {
  BodyRepository(this._engine, this._onChange);
  final SyncEngine _engine;
  final void Function() _onChange;

  /// [json] trae lo que el usuario puede cambiar (peso, cintura y, sin diario, kcal y proteína);
  /// lo demás del registro se conserva.
  Future<void> saveEntry(DateTime date, Map<String, dynamic> json) async {
    final id = isoDate(date);
    final current = decodeData(await _engine.db.record('body_entry', id)) ?? {};
    final weightChanged = current['weight_kg'] != json['weight_kg'];
    await _engine.put('body_entry', id, {
      'date': id,
      'weight_kg': current['weight_kg'],
      'waist_cm': current['waist_cm'],
      'kcal': current['kcal'],
      'protein_g': current['protein_g'],
      ...json,
      // Como hace el servidor: el peso que cambias tú pasa a ser manual
      'weight_source': weightChanged ? (json['weight_kg'] == null ? null : 'manual') : current['weight_source'],
    });
    _onChange();
  }

  Future<void> deleteEntry(DateTime date) async {
    await _engine.remove('body_entry', isoDate(date));
    _onChange();
  }

  /// [json]: los campos del formulario; el resto del perfil (nombre, plan activo…) se conserva.
  Future<void> saveProfile(Map<String, dynamic> json) async {
    final current = decodeData(await _engine.db.record('profile', 'me')) ?? defaultProfileData;
    await _engine.put('profile', 'me', {...current, ...json});
    _onChange();
  }
}

/// Antes de la primera descarga (sin conexión al estrenar la versión) se usan los valores por defecto del servidor.
const defaultProfileData = <String, dynamic>{
  'name': '',
  'start_date': null,
  'start_weight_kg': null,
  'start_body_fat_pct': null,
  'kcal_target': 2000,
  'protein_target_g': 160,
  'program_id': null,
  'program_started_on': null,
};

final bodyRepositoryProvider = Provider<BodyRepository>(
  (ref) => BodyRepository(ref.watch(syncEngineProvider), () => ref.read(syncControllerProvider.notifier).changed()),
);

final profileProvider = Provider<AsyncValue<Profile>>(
  (ref) => ref.watch(localRecordsProvider('profile')).whenData((r) => Profile.fromJson(r['me'] ?? defaultProfileData)),
);

/// Resumen de Peso calculado en el móvil con lo que hay en local: se actualiza al momento al guardar.
final bodySummaryProvider = Provider<AsyncValue<BodySummary>>((ref) {
  final entries = ref.watch(localRecordsProvider('body_entry'));
  final health = ref.watch(localRecordsProvider('health_day'));
  final profile = ref.watch(profileProvider);
  final diary = ref.watch(diaryTotalsProvider);
  if (entries.hasError) return AsyncError(entries.error!, entries.stackTrace!);
  if (!entries.hasValue || !health.hasValue || !profile.hasValue || !diary.hasValue) return const AsyncLoading();
  return AsyncData(computeSummary(
    [for (final e in entries.value!.values) BodyEntry.fromJson(e)],
    profile.value,
    health.value!.values.toList(),
    diary: diary.value!,
  ));
});
