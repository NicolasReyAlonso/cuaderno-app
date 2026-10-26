import 'dart:math';

import 'package:dio/dio.dart';

import 'local_db.dart';

/// Un registro tal como lo da el servidor (SyncRecord en el backend).
class RemoteRecord {
  final String entity, id;
  final int version;
  final bool deleted;
  final Map<String, dynamic>? data;
  const RemoteRecord({required this.entity, required this.id, required this.version, this.deleted = false, this.data});

  factory RemoteRecord.fromJson(Map<String, dynamic> j) => RemoteRecord(
        entity: j['entity'] as String,
        id: j['id'] as String,
        version: j['version'] as int,
        deleted: j['deleted'] as bool? ?? false,
        data: j['data'] as Map<String, dynamic>?,
      );

  Map<String, dynamic> toJson() => {'entity': entity, 'id': id, 'version': version, 'deleted': deleted, 'data': data};
}

class PullPage {
  final int cursor;
  final bool more;
  final List<RemoteRecord> changes;
  const PullPage(this.cursor, this.more, this.changes);
}

/// status: applied | conflict | rejected.
class PushResult {
  final String opId, status;
  final int? version;
  final RemoteRecord? server;
  final String? detail;
  const PushResult(this.opId, this.status, {this.version, this.server, this.detail});

  factory PushResult.fromJson(Map<String, dynamic> j) => PushResult(
        j['op_id'] as String,
        j['status'] as String,
        version: j['version'] as int?,
        server: j['server'] == null ? null : RemoteRecord.fromJson(j['server'] as Map<String, dynamic>),
        detail: j['detail'] as String?,
      );
}

/// El servidor no responde (sin red, apagado, Tailscale caído…). Los cambios esperan en la cola.
class OfflineException implements Exception {
  const OfflineException();
  @override
  String toString() => 'Sin conexión con el servidor.';
}

abstract class SyncApi {
  Future<PullPage> pull(int since);
  Future<List<PushResult>> push(List<OutboxOp> ops);

  /// Datos de consulta (GET /sync/reference). null si no cambiaron desde [knownHash].
  Future<Map<String, dynamic>?> reference(String? knownHash);
}

class DioSyncApi implements SyncApi {
  DioSyncApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // Sin respuesta o el servidor caído/arrancando: es «sin conexión», no un error de datos
      if (code == null || code >= 500) throw const OfflineException();
      rethrow;
    }
  }

  @override
  Future<PullPage> pull(int since) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('/sync/pull', queryParameters: {'since': since});
        final j = r.data!;
        return PullPage(j['cursor'] as int, j['more'] as bool, [for (final c in j['changes'] as List) RemoteRecord.fromJson(c as Map<String, dynamic>)]);
      });

  @override
  Future<Map<String, dynamic>?> reference(String? knownHash) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('/sync/reference', queryParameters: {if (knownHash != null) 'known': knownHash});
        return r.data!['unchanged'] == true ? null : r.data!;
      });

  @override
  Future<List<PushResult>> push(List<OutboxOp> ops) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('/sync/push', data: {
          'changes': [
            for (final o in ops)
              {'op_id': o.opId, 'entity': o.entity, 'id': o.recordId, 'base_version': o.baseVersion, 'data': decode(o.data), 'delete': o.isDelete},
          ],
        });
        return [for (final x in r.data!['results'] as List) PushResult.fromJson(x as Map<String, dynamic>)];
      });
}

final _rnd = Random.secure();

/// UUID v4 para identificar cada cambio (el servidor no aplica dos veces el mismo).
String uuidV4() {
  final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
