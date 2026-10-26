import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api.dart';
import '../../core/local/sync_controller.dart';
import 'health_models.dart';
import 'health_reader.dart';

class HealthRepository {
  HealthRepository(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> sync(List<Map<String, dynamic>> days, List<Map<String, dynamic>> activities) async {
    final r = await _dio.post<Map<String, dynamic>>('/health/sync', data: {'days': days, 'activities': activities});
    return r.data!;
  }

  Future<void> forget() => _dio.delete<void>('/health');
}

final healthRepositoryProvider = Provider<HealthRepository>((ref) => HealthRepository(ref.watch(dioProvider)));
final healthReaderProvider = Provider<HealthReader>((ref) => HealthReader());

/// Actividades de los últimos 30 días, de la base local (llegan con la sincronización; se ven también en Mac y web).
final healthActivitiesProvider = Provider<AsyncValue<List<ActivityRecord>>>((ref) {
  final since = DateTime.now().subtract(const Duration(days: 30));
  return ref.watch(localRecordsProvider('activity')).whenData((rows) =>
      [for (final a in rows.values) ActivityRecord.fromJson(a)].where((a) => a.start.isAfter(since)).toList()..sort((a, b) => b.start.compareTo(a.start)));
});

class HealthState {
  final bool supported, connected, syncing;
  final String? problem; // qué falta para poder usarlo (p. ej. instalar Health Connect)
  final String? message;
  final bool messageIsError;
  final DateTime? lastSync;
  const HealthState({this.supported = false, this.connected = false, this.syncing = false, this.problem, this.message, this.messageIsError = false, this.lastSync});

  HealthState copyWith({bool? connected, bool? syncing, String? message, bool? messageIsError, DateTime? lastSync, String? problem}) => HealthState(
        supported: supported,
        connected: connected ?? this.connected,
        syncing: syncing ?? this.syncing,
        problem: problem ?? this.problem,
        message: message,
        messageIsError: messageIsError ?? false,
        lastSync: lastSync ?? this.lastSync,
      );
}

/// Conectar, sincronizar y desconectar. «Conectado» se recuerda en el móvil: en iPhone,
/// Salud no deja saber si se concedió el permiso de lectura.
class HealthController extends AsyncNotifier<HealthState> {
  static const _key = 'health_connected';
  final _store = const FlutterSecureStorage(mOptions: MacOsOptions(useDataProtectionKeyChain: false));

  HealthReader get _reader => ref.read(healthReaderProvider);

  @override
  Future<HealthState> build() async {
    final reader = _reader;
    if (!reader.supported) return const HealthState();
    String? problem;
    try {
      problem = await reader.problem();
    } catch (e) {
      problem = 'No se pudo abrir ${reader.storeName}: $e';
    }
    final connected = problem == null && await _store.read(key: _key) == '1';
    return HealthState(supported: true, connected: connected, problem: problem);
  }

  HealthState get _s => state.valueOrNull ?? const HealthState();

  Future<void> connect() async {
    try {
      if (!await _reader.connect()) {
        state = AsyncData(_s.copyWith(message: 'No has dado permiso. Puedes darlo desde ${_reader.storeName} → Permisos de apps.', messageIsError: true));
        return;
      }
      await _store.write(key: _key, value: '1');
      state = AsyncData(_s.copyWith(connected: true));
      await sync();
    } catch (e) {
      state = AsyncData(_s.copyWith(message: 'No se pudo conectar con ${_reader.storeName}: $e', messageIsError: true));
    }
  }

  /// Lee los últimos 30 días y los manda al servidor. [silent]: sin mensaje si todo va bien.
  Future<void> sync({bool silent = false}) async {
    final s = _s;
    if (!s.connected || s.syncing) return;
    state = AsyncData(s.copyWith(syncing: true, message: silent ? null : 'Leyendo ${_reader.storeName}…'));
    try {
      final data = await _reader.read();
      final r = await ref.read(healthRepositoryProvider).sync(data.days, data.activities);
      await ref.read(syncControllerProvider.notifier).syncNow(); // lo nuevo baja a la base local
      state = AsyncData(_s.copyWith(syncing: false, lastSync: DateTime.now(), message: silent ? null : syncMessage(r)));
    } catch (e) {
      state = AsyncData(_s.copyWith(syncing: false, message: silent ? null : apiMessage(e), messageIsError: !silent));
    }
  }

  Future<void> syncIfConnected() async {
    await future;
    await sync(silent: true);
  }

  /// Quita el permiso (Android) y borra del servidor todo lo que vino de la pulsera y la báscula.
  Future<void> disconnect() async {
    try {
      await ref.read(healthRepositoryProvider).forget();
      await _reader.disconnect();
      await _store.delete(key: _key);
      await ref.read(syncControllerProvider.notifier).syncNow();
      state = AsyncData(_s.copyWith(
          connected: false,
          message: _reader.isAndroid ? 'Desconectado y datos de salud borrados.' : 'Datos borrados. Quita el permiso en Salud → Apps → cuaderno.'));
    } catch (e) {
      state = AsyncData(_s.copyWith(message: apiMessage(e), messageIsError: true));
    }
  }

  Future<void> install() => _reader.installHealthConnect();
}

final healthProvider = AsyncNotifierProvider<HealthController, HealthState>(HealthController.new);
