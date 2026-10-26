import 'dart:convert';

import 'package:drift/drift.dart';

import 'local_db.dart';
import 'sync_api.dart';

/// Resultado de una sincronización completa.
class SyncReport {
  int applied = 0, conflicts = 0, rejected = 0, pulled = 0;
  final Set<String> changedEntities = {}; // tipos que llegaron cambiados del servidor
}

/// Escrituras locales con cola de pendientes, envío y descarga.
///
/// - put / remove: la pantalla lo ve al momento (se lee de la base local) y queda en la cola.
///   Si ya había un cambio sin enviar del mismo registro, se juntan en uno.
/// - sync: envía la cola en orden (como mucho un cambio por registro en cada tanda) y
///   descarga lo que cambió en el servidor. Si no hay conexión lanza OfflineException y
///   la cola queda como estaba.
/// - Conflicto: el cambio se queda en la cola, parado, hasta que el usuario elige
///   keepMine (se reenvía sobre la versión del servidor) o keepServer (se descarta).
class SyncEngine {
  SyncEngine(this.db, this.api);
  final LocalDb db;
  final SyncApi api;

  /// Qué tipos sincroniza esta versión de la app. Al ampliarlo (Comidas, Entreno, Planes) lo que ya
  /// existía de los tipos nuevos no está en las descargas incrementales: se hace una completa.
  /// 1 = Peso y perfil; 2 = + comidas.
  static const scope = 2;

  // ---------------------------------------------------------------- escrituras locales
  Future<void> put(String entity, String id, Map<String, dynamic> data) => _write(entity, id, data, false);

  Future<void> remove(String entity, String id) => _write(entity, id, null, true);

  Future<void> _write(String entity, String id, Map<String, dynamic>? data, bool delete) => db.transaction(() async {
        final rec = await db.record(entity, id);
        final ops = await db.opsOf(entity, id);
        final serverVersion = rec?.serverVersion ?? 0;

        // Borrar algo que el servidor nunca tuvo y que aún no se ha enviado: basta con olvidarlo
        if (delete && serverVersion == 0 && ops.every((o) => o.state == 'pending')) {
          for (final o in ops) {
            await (db.delete(db.outbox)..where((x) => x.seq.equals(o.seq))).go();
          }
          await db.removeRecord(entity, id);
          return;
        }

        await db.upsertRecord(RecordsCompanion(
          entity: Value(entity),
          id: Value(id),
          data: Value(delete ? null : jsonEncode(data)),
          deleted: Value(delete),
          day: delete ? const Value.absent() : Value(dayOf(data)),
        ));

        final last = ops.isEmpty ? null : ops.last;
        if (last != null && last.state == 'pending') {
          await (db.update(db.outbox)..where((o) => o.seq.equals(last.seq)))
              .write(OutboxCompanion(data: Value(delete ? null : jsonEncode(data)), isDelete: Value(delete)));
        } else {
          await db.into(db.outbox).insert(OutboxCompanion.insert(
                opId: uuidV4(),
                entity: entity,
                recordId: id,
                baseVersion: serverVersion,
                data: Value(delete ? null : jsonEncode(data)),
                isDelete: Value(delete),
              ));
        }
      });

  // ---------------------------------------------------------------- sincronizar
  Future<SyncReport> sync() async {
    final report = SyncReport();
    // Un envío que se cortó a medias (app cerrada) vuelve a la cola: el servidor no lo aplica dos veces
    await (db.update(db.outbox)..where((o) => o.state.equals('sending'))).write(const OutboxCompanion(state: Value('pending')));

    while (true) {
      final batch = await _sendable();
      if (batch.isEmpty) break;
      await _setState(batch, 'sending');
      final List<PushResult> results;
      try {
        results = await api.push(batch);
      } catch (_) {
        await _setState(batch, 'pending');
        rethrow;
      }
      await db.transaction(() async {
        final answered = <String>{};
        for (final r in results) {
          answered.add(r.opId);
          await _handle(r, report);
        }
        await _setState([for (final o in batch) if (!answered.contains(o.opId)) o], 'pending');
      });
    }

    if ((int.tryParse(await db.readMeta('scope') ?? '') ?? 1) < scope) await db.setMeta('cursor', '0');
    var cursor = int.tryParse(await db.readMeta('cursor') ?? '') ?? 0;
    final snapshot = cursor == 0;
    final seen = <(String, String)>{};
    while (true) {
      final page = await api.pull(cursor);
      await db.transaction(() async {
        for (final c in page.changes) {
          seen.add((c.entity, c.id));
          if (await _applyRemote(c)) {
            report.pulled++;
            report.changedEntities.add(c.entity);
          }
        }
        if (snapshot && !page.more) await _dropMissing(seen);
        await db.setMeta('cursor', '${page.cursor}');
      });
      cursor = page.cursor;
      if (!page.more) break;
    }
    // Datos de consulta comunes (alimentos del catálogo…): solo se descargan si cambiaron
    final ref = await api.reference(await db.readMeta('ref_hash'));
    if (ref != null) {
      await db.setMeta('ref_data', jsonEncode(ref));
      await db.setMeta('ref_hash', ref['hash'] as String);
      report.changedEntities.add('reference');
    }
    await db.setMeta('scope', '$scope');
    await db.setMeta('last_sync', DateTime.now().toIso8601String());
    return report;
  }

  /// Cambios que se pueden enviar ya: en orden, uno por registro, y nada de un registro con un
  /// conflicto o rechazo pendiente (los siguientes se apoyan en él).
  Future<List<OutboxOp>> _sendable({int limit = 200}) async {
    final all = await (db.select(db.outbox)..orderBy([(o) => OrderingTerm(expression: o.seq)])).get();
    final blocked = <(String, String)>{};
    final out = <OutboxOp>[];
    for (final o in all) {
      final key = (o.entity, o.recordId);
      if (blocked.contains(key)) continue;
      blocked.add(key);
      if (o.state == 'pending') out.add(o);
      if (out.length == limit) break;
    }
    return out;
  }

  Future<void> _setState(List<OutboxOp> ops, String state) async {
    for (final o in ops) {
      await (db.update(db.outbox)..where((x) => x.seq.equals(o.seq))).write(OutboxCompanion(state: Value(state)));
    }
  }

  Future<void> _rememberServer(RemoteRecord s) async {
    final rec = await db.record(s.entity, s.id);
    if (rec != null && s.version < rec.serverVersion) return; // ya sabíamos algo más nuevo
    await db.upsertRecord(RecordsCompanion(
      entity: Value(s.entity),
      id: Value(s.id),
      serverVersion: Value(s.version),
      serverData: Value(s.data == null ? null : jsonEncode(s.data)),
      serverDeleted: Value(s.deleted),
      // Registro nuevo para la base local: que se vea como en el servidor
      data: rec == null ? Value(s.data == null ? null : jsonEncode(s.data)) : const Value.absent(),
      deleted: rec == null ? Value(s.deleted) : const Value.absent(),
      day: rec == null ? Value(dayOf(s.data)) : const Value.absent(),
    ));
  }

  /// Sin cambios locales pendientes, lo visible pasa a ser lo del servidor (o desaparece si se borró).
  Future<void> _settleIfClean(String entity, String id) async {
    if ((await db.opsOf(entity, id)).isNotEmpty) return;
    final rec = await db.record(entity, id);
    if (rec == null) return;
    if (rec.serverDeleted || rec.serverVersion == 0) {
      await db.removeRecord(entity, id);
    } else {
      await db.upsertRecord(RecordsCompanion(
          entity: Value(entity), id: Value(id), data: Value(rec.serverData), deleted: const Value(false), day: Value(dayOf(decode(rec.serverData)))));
    }
  }

  Future<void> _handle(PushResult r, SyncReport report) async {
    final op = await db.op(r.opId);
    if (op == null) return;
    final where = db.update(db.outbox)..where((o) => o.seq.equals(op.seq));
    switch (r.status) {
      case 'applied':
        await (db.delete(db.outbox)..where((o) => o.seq.equals(op.seq))).go();
        if (r.server != null) await _rememberServer(r.server!);
        // Los cambios posteriores del mismo registro se hicieron sobre este: se apoyan en la versión nueva
        await (db.update(db.outbox)..where((o) => o.entity.equals(op.entity) & o.recordId.equals(op.recordId)))
            .write(OutboxCompanion(baseVersion: Value(r.version ?? r.server?.version ?? op.baseVersion)));
        await _settleIfClean(op.entity, op.recordId);
        report.applied++;
      case 'conflict':
        if (r.server != null) await _rememberServer(r.server!);
        await where.write(OutboxCompanion(state: const Value('conflict'), serverRecord: Value(jsonEncode(r.server?.toJson()))));
        report.conflicts++;
      default:
        await where.write(OutboxCompanion(state: const Value('rejected'), detail: Value(r.detail ?? 'El servidor no lo aceptó.')));
        report.rejected++;
    }
  }

  /// Aplica un cambio que llega del servidor. Devuelve true si cambió lo que ve el usuario.
  Future<bool> _applyRemote(RemoteRecord c) async {
    final before = await db.record(c.entity, c.id);
    if (before != null && c.version < before.serverVersion) return false;
    await _rememberServer(c);
    await _settleIfClean(c.entity, c.id);
    final after = await db.record(c.entity, c.id);
    return before?.data != after?.data || (before == null) != (after == null);
  }

  /// Primera descarga: lo que hay en local y no en el servidor (y sin cambios pendientes) sobra.
  Future<void> _dropMissing(Set<(String, String)> seen) async {
    for (final r in await db.select(db.records).get()) {
      if (seen.contains((r.entity, r.id))) continue;
      if ((await db.opsOf(r.entity, r.id)).isEmpty) await db.removeRecord(r.entity, r.id);
    }
  }

  // ---------------------------------------------------------------- resolver
  /// Conflicto: «quedarme con lo mío». Se reenvía sobre la versión del servidor.
  Future<void> keepMine(OutboxOp op) async {
    final server = op.serverRecord == null ? null : RemoteRecord.fromJson(decode(op.serverRecord)!);
    await (db.update(db.outbox)..where((o) => o.seq.equals(op.seq))).write(OutboxCompanion(
          // Operación nueva: con el mismo op_id el servidor devolvería el conflicto que ya tiene guardado
          opId: Value(uuidV4()),
          state: const Value('pending'),
          baseVersion: Value(server?.version ?? op.baseVersion),
          serverRecord: const Value(null),
        ));
  }

  /// Conflicto: «quedarme con lo del servidor». Se descartan los cambios locales de ese registro.
  Future<void> keepServer(OutboxOp op) => db.transaction(() async {
        await (db.delete(db.outbox)..where((o) => o.entity.equals(op.entity) & o.recordId.equals(op.recordId))).go();
        await _settleIfClean(op.entity, op.recordId);
      });

  /// Rechazado: se descarta ese cambio. Si no quedan otros del registro, vuelve a lo del servidor.
  Future<void> discard(OutboxOp op) => db.transaction(() async {
        await (db.delete(db.outbox)..where((o) => o.seq.equals(op.seq))).go();
        await _settleIfClean(op.entity, op.recordId);
      });
}
