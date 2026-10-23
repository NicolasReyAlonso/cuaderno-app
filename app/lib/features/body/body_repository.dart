import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../nutrition/nutrition_repository.dart' show diaryDayProvider;
import '../workout/workout_repository.dart' show isoDate;
import 'models.dart';

class BodyRepository {
  BodyRepository(this._dio);
  final Dio _dio;

  Future<BodySummary> summary() async {
    final r = await _dio.get<Map<String, dynamic>>('/body/summary');
    return BodySummary.fromJson(r.data!);
  }

  Future<void> saveEntry(DateTime date, Map<String, dynamic> json) => _dio.put<void>('/body/${isoDate(date)}', data: json);

  Future<void> deleteEntry(DateTime date) => _dio.delete<void>('/body/${isoDate(date)}');

  Future<Profile> profile() async {
    final r = await _dio.get<Map<String, dynamic>>('/me');
    return Profile.fromJson(r.data!);
  }

  Future<Profile> saveProfile(Map<String, dynamic> json) async {
    final r = await _dio.patch<Map<String, dynamic>>('/me', data: json);
    return Profile.fromJson(r.data!);
  }
}

final bodyRepositoryProvider = Provider<BodyRepository>((ref) => BodyRepository(ref.watch(dioProvider)));

final bodySummaryProvider = FutureProvider.autoDispose<BodySummary>((ref) => ref.watch(bodyRepositoryProvider).summary());

final profileProvider = FutureProvider.autoDispose<Profile>((ref) => ref.watch(bodyRepositoryProvider).profile());

/// Tras cambiar el punto de partida o los objetivos: el resumen y los totales de Comidas cambian.
void refreshAfterProfileChange(WidgetRef ref) {
  ref.invalidate(profileProvider);
  ref.invalidate(bodySummaryProvider);
  ref.invalidate(diaryDayProvider);
}
