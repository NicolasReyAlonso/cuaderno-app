import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import 'local_db.dart';
import 'sync_api.dart';
import 'sync_engine.dart';

final localDbProvider = Provider<LocalDb>((ref) {
  final db = LocalDb.open();
  ref.onDispose(db.close);
  return db;
});

final syncEngineProvider = Provider<SyncEngine>((ref) => SyncEngine(ref.watch(localDbProvider), DioSyncApi(ref.watch(dioProvider))));

/// La cola de cambios, en vivo: para el indicador y la pantalla de conflictos.
final outboxProvider = StreamProvider<List<OutboxOp>>((ref) => ref.watch(localDbProvider).watchOutbox());

/// Registros visibles de un tipo, ya decodificados: {id: datos}. Se actualiza solo al escribir o sincronizar.
final localRecordsProvider = StreamProvider.family<Map<String, Map<String, dynamic>>, String>((ref, entity) =>
    ref.watch(localDbProvider).watchEntity(entity).map((rows) => {for (final r in rows) if (r.data != null) r.id: jsonDecode(r.data!) as Map<String, dynamic>}));

class SyncStatus {
  final bool syncing;
  final bool? online; // null = aún no se ha intentado
  final DateTime? lastSync;
  final String? error;
  const SyncStatus({this.syncing = false, this.online, this.lastSync, this.error});

  SyncStatus copyWith({bool? syncing, bool? online, DateTime? lastSync, String? error}) =>
      SyncStatus(syncing: syncing ?? this.syncing, online: online ?? this.online, lastSync: lastSync ?? this.lastSync, error: error);
}

/// Cuándo sincronizar: al abrir, poco después de cada cambio, al volver a la app y cada 30 s
/// mientras haya algo por enviar (o cada 2 min para recibir lo de otros dispositivos).
class SyncController extends Notifier<SyncStatus> {
  Timer? _timer, _debounce;
  AppLifecycleListener? _life;
  bool _running = false, _again = false;

  /// Al acabar cada sincronización con cambios recibidos: los pasos siguientes (comidas, entreno)
  /// registran aquí qué pantallas que aún leen del servidor hay que refrescar.
  static final List<void Function(Ref ref, Set<String> changed)> afterPull = [];

  @override
  SyncStatus build() {
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    _life = AppLifecycleListener(onResume: syncNow);
    ref.onDispose(() {
      _timer?.cancel();
      _debounce?.cancel();
      _life?.dispose();
    });
    return const SyncStatus();
  }

  Future<void> _tick() async {
    final pending = (await ref.read(localDbProvider).watchOutbox().first).any((o) => o.state == 'pending');
    final stale = state.lastSync == null || DateTime.now().difference(state.lastSync!) > const Duration(minutes: 2);
    if (pending || stale) await syncNow();
  }

  /// Tras un cambio local: espera un momento por si llegan más y sincroniza.
  void changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), syncNow);
  }

  Future<void> syncNow() async {
    if (await ref.read(tokenStoreProvider).read() == null) return; // sin sesión
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    state = state.copyWith(syncing: true);
    try {
      final report = await ref.read(syncEngineProvider).sync();
      state = SyncStatus(online: true, lastSync: DateTime.now());
      if (report.changedEntities.isNotEmpty) {
        for (final f in afterPull) {
          f(ref, report.changedEntities);
        }
      }
    } on OfflineException {
      state = state.copyWith(syncing: false, online: false);
    } catch (e) {
      state = state.copyWith(syncing: false, error: apiMessage(e));
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        unawaited(syncNow());
      }
    }
  }

  /// Al iniciar sesión: si la base local es de otra cuenta, se vacía antes de descargar.
  Future<void> onLogin() async {
    final db = ref.read(localDbProvider);
    try {
      final me = await ref.read(dioProvider).get<Map<String, dynamic>>('/me');
      final id = me.data!['id'] as String;
      if (await db.readMeta('user_id') != id) {
        await db.wipe();
        await db.setMeta('user_id', id);
      }
    } catch (_) {
      // Sin conexión justo tras iniciar sesión: se comprobará en la siguiente
    }
    await syncNow();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);
