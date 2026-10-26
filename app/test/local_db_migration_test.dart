import 'dart:io';

import 'package:cuaderno/core/local/local_db.dart';
import 'package:drift/drift.dart' show OpeningDetails, QueryExecutor, QueryExecutorUser, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Abre la base sin migraciones: solo para crearla con el esquema viejo.
class _Raw implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}

/// La base tal como la dejaba la versión 1 (paso 2: solo Peso), con registros dentro.
Future<void> _createV1(String path) async {
  final db = NativeDatabase(File(path), setup: (raw) => raw.execute('''
    CREATE TABLE records (entity TEXT NOT NULL, id TEXT NOT NULL, data TEXT NULL,
      deleted INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0, 1)), server_version INTEGER NOT NULL DEFAULT 0,
      server_data TEXT NULL, server_deleted INTEGER NOT NULL DEFAULT 0 CHECK (server_deleted IN (0, 1)), PRIMARY KEY (entity, id));
    CREATE TABLE outbox (seq INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, op_id TEXT NOT NULL, entity TEXT NOT NULL,
      record_id TEXT NOT NULL, base_version INTEGER NOT NULL, data TEXT NULL, is_delete INTEGER NOT NULL DEFAULT 0 CHECK (is_delete IN (0, 1)),
      state TEXT NOT NULL DEFAULT 'pending', server_record TEXT NULL, detail TEXT NULL,
      created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
    CREATE TABLE meta ("key" TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY ("key"));
    INSERT INTO records (entity, id, data, server_version) VALUES ('body_entry', '2026-10-20', '{"date":"2026-10-20","weight_kg":98.1}', 2);
    INSERT INTO records (entity, id, data, server_version) VALUES ('profile', 'me', '{"kcal_target":2000}', 1);
    INSERT INTO meta ("key", value) VALUES ('cursor', '17');
    PRAGMA user_version = 1;
  '''));
  await db.ensureOpen(_Raw());
  await db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('una base de la versión 1 pasa a la 2 sin perder nada y con la fecha rellena', () async {
    final dir = await Directory.systemTemp.createTemp('cuaderno_db');
    final path = '${dir.path}/cuaderno.sqlite';
    await _createV1(path);

    final db = LocalDb(NativeDatabase(File(path)));
    final weight = await db.record('body_entry', '2026-10-20');
    expect((weight!.serverVersion, weight.day), (2, '2026-10-20'));
    expect((await db.record('profile', 'me'))!.day, isNull);
    expect(await db.readMeta('cursor'), '17'); // no hace falta volver a descargarlo todo
    expect((await db.watchDay('body_entry', '2026-10-20').first).single.id, '2026-10-20');
    await db.close();
    await dir.delete(recursive: true);
  });
}
