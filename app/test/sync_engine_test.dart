import 'package:cuaderno/core/local/local_db.dart';
import 'package:cuaderno/core/local/sync_api.dart';
import 'package:cuaderno/core/local/sync_engine.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Servidor de mentira con las mismas reglas que backend/app/routers/sync.py.
class FakeServer implements SyncApi {
  final Map<(String, String), ({int version, bool deleted, Map<String, dynamic>? data})> rows = {};
  final List<(int, String, String)> log = []; // (seq, entity, id)
  final Map<String, PushResult> doneOps = {};
  int _seq = 0;
  bool offline = false;
  int pushCalls = 0;
  List<List<String>> batches = [];

  void _log(String e, String id) => log.add((++_seq, e, id));

  /// Un cambio hecho «en otro dispositivo».
  void edit(String e, String id, Map<String, dynamic>? data) {
    final cur = rows[(e, id)];
    rows[(e, id)] = (version: (cur?.version ?? 0) + 1, deleted: data == null, data: data);
    _log(e, id);
  }

  RemoteRecord _rec(String e, String id) {
    final r = rows[(e, id)];
    return RemoteRecord(entity: e, id: id, version: r?.version ?? 0, deleted: r == null || r.deleted, data: r?.deleted ?? true ? null : r!.data);
  }

  @override
  Future<PullPage> pull(int since) async {
    if (offline) throw const OfflineException();
    if (since == 0) {
      return PullPage(_seq, false, [for (final k in rows.keys) if (!rows[k]!.deleted) _rec(k.$1, k.$2)]);
    }
    final keys = <(String, String)>[];
    var cursor = since;
    for (final (seq, e, id) in log) {
      if (seq <= since) continue;
      keys.remove((e, id));
      keys.add((e, id));
      cursor = seq;
    }
    return PullPage(cursor, false, [for (final k in keys) _rec(k.$1, k.$2)]);
  }

  Map<String, dynamic>? referenceData;

  @override
  Future<Map<String, dynamic>?> reference(String? knownHash) async => referenceData?['hash'] == knownHash ? null : referenceData;

  @override
  Future<List<PushResult>> push(List<OutboxOp> ops) async {
    if (offline) throw const OfflineException();
    pushCalls++;
    batches.add([for (final o in ops) o.recordId]);
    return [
      for (final o in ops) doneOps[o.opId] ??= _apply(o),
    ];
  }

  PushResult _apply(OutboxOp o) {
    final key = (o.entity, o.recordId);
    final cur = rows[key];
    final exists = cur != null && !cur.deleted;
    final current = cur?.version ?? 0;
    final data = decode(o.data);
    if ((data?['weight_kg'] as num?) == 10) return PushResult(o.opId, 'rejected', detail: 'Revisa «weight_kg»');
    if (o.isDelete) {
      if (!exists) return PushResult(o.opId, 'applied', version: current, server: _rec(o.entity, o.recordId));
      if (o.baseVersion != current) return PushResult(o.opId, 'conflict', server: _rec(o.entity, o.recordId));
      edit(o.entity, o.recordId, null);
      return PushResult(o.opId, 'applied', version: current + 1, server: _rec(o.entity, o.recordId));
    }
    final stale = o.baseVersion != current && (exists || o.baseVersion > 0);
    if (stale) {
      if (exists && cur.data.toString() == data.toString()) {
        return PushResult(o.opId, 'applied', version: current, server: _rec(o.entity, o.recordId));
      }
      return PushResult(o.opId, 'conflict', server: _rec(o.entity, o.recordId));
    }
    edit(o.entity, o.recordId, data);
    return PushResult(o.opId, 'applied', version: current + 1, server: _rec(o.entity, o.recordId));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late LocalDb db;
  late FakeServer server;
  late SyncEngine engine;

  setUp(() {
    db = LocalDb(NativeDatabase.memory());
    server = FakeServer();
    engine = SyncEngine(db, server);
  });
  tearDown(() => db.close());

  Future<Map<String, dynamic>?> local(String id) async => decode((await db.record('body_entry', id))?.data);
  Future<List<OutboxOp>> queue() => db.select(db.outbox).get();

  test('sin servidor se guarda en local y en la cola; al volver se envía y se descarga', () async {
    server.edit('profile', 'me', {'kcal_target': 2000});
    await engine.sync(); // primera descarga
    expect(decode((await db.record('profile', 'me'))!.data), {'kcal_target': 2000});

    server.offline = true;
    await engine.put('body_entry', '2026-10-20', {'weight_kg': 98.1});
    await engine.put('body_entry', '2026-10-20', {'weight_kg': 98.0}); // se junta con el anterior
    expect(await local('2026-10-20'), {'weight_kg': 98.0});
    expect((await queue()).length, 1);
    await expectLater(engine.sync(), throwsA(isA<OfflineException>()));
    expect((await queue()).single.state, 'pending'); // nada se pierde

    server.offline = false;
    final r = await engine.sync();
    expect(r.applied, 1);
    expect(await queue(), isEmpty);
    expect(server.rows[('body_entry', '2026-10-20')]!.data, {'weight_kg': 98.0});
    expect((await db.record('body_entry', '2026-10-20'))!.serverVersion, 1);
  });

  test('lo cambiado en otro dispositivo llega; lo borrado desaparece', () async {
    server.edit('body_entry', '2026-10-20', {'weight_kg': 98.1});
    await engine.sync();
    server.edit('body_entry', '2026-10-20', {'weight_kg': 97.9});
    server.edit('body_entry', '2026-10-21', {'weight_kg': 97.7});
    final r = await engine.sync();
    expect(r.pulled, 2);
    expect(r.changedEntities, {'body_entry'});
    expect(await local('2026-10-20'), {'weight_kg': 97.9});
    server.edit('body_entry', '2026-10-21', null);
    await engine.sync();
    expect(await db.record('body_entry', '2026-10-21'), isNull);
  });

  test('un cambio sin enviar no se pisa con lo que llega del servidor', () async {
    server.edit('body_entry', '2026-10-20', {'weight_kg': 98.1});
    await engine.sync();
    server.offline = true;
    await engine.put('body_entry', '2026-10-20', {'weight_kg': 97.5});
    server.offline = false;
    server.edit('body_entry', '2026-10-20', {'weight_kg': 99.0}); // otro dispositivo, mientras tanto
    final r = await engine.sync();
    expect(r.conflicts, 1);
    expect(await local('2026-10-20'), {'weight_kg': 97.5}); // sigue viéndose lo tuyo hasta que elijas
    final op = (await queue()).single;
    expect(op.state, 'conflict');
    expect(RemoteRecord.fromJson(decode(op.serverRecord)!).data, {'weight_kg': 99.0});
  });

  test('conflicto: quedarme con lo mío lo reenvía sobre la versión del servidor', () async {
    server.edit('body_entry', '2026-10-20', {'weight_kg': 98.1});
    await engine.sync();
    await engine.put('body_entry', '2026-10-20', {'weight_kg': 97.5});
    server.edit('body_entry', '2026-10-20', {'weight_kg': 99.0});
    await engine.sync();
    await engine.keepMine((await queue()).single);
    await engine.sync();
    expect(await queue(), isEmpty);
    expect(server.rows[('body_entry', '2026-10-20')]!.data, {'weight_kg': 97.5});
    expect(await local('2026-10-20'), {'weight_kg': 97.5});
  });

  test('conflicto: quedarme con lo del servidor descarta lo local', () async {
    server.edit('body_entry', '2026-10-20', {'weight_kg': 98.1});
    await engine.sync();
    await engine.put('body_entry', '2026-10-20', {'weight_kg': 97.5});
    server.edit('body_entry', '2026-10-20', {'weight_kg': 99.0});
    await engine.sync();
    await engine.keepServer((await queue()).single);
    expect(await queue(), isEmpty);
    expect(await local('2026-10-20'), {'weight_kg': 99.0});
  });

  test('los cambios hechos mientras se enviaba otro no chocan contigo mismo', () async {
    server.edit('body_entry', '2026-10-20', {'weight_kg': 98.1});
    await engine.sync();
    await engine.put('body_entry', '2026-10-20', {'weight_kg': 98.0});
    // Simula que el primero ya salió (estado sending) y el usuario vuelve a cambiarlo
    await (db.update(db.outbox)).write(const OutboxCompanion(state: Value('sending')));
    await engine.put('body_entry', '2026-10-20', {'weight_kg': 97.9});
    expect((await queue()).length, 2);
    final r = await engine.sync();
    expect((r.applied, r.conflicts), (2, 0));
    expect(server.batches, [['2026-10-20'], ['2026-10-20']]); // uno por tanda: el segundo, ya sobre la versión nueva
    expect(server.rows[('body_entry', '2026-10-20')]!.data, {'weight_kg': 97.9});
  });

  test('rechazado: se para ese registro y al descartarlo vuelve lo del servidor', () async {
    server.edit('body_entry', '2026-10-20', {'weight_kg': 98.1});
    await engine.sync();
    await engine.put('body_entry', '2026-10-20', {'weight_kg': 10});
    await engine.put('body_entry', '2026-10-21', {'weight_kg': 97.7});
    final r = await engine.sync();
    expect((r.applied, r.rejected), (1, 1)); // el otro registro sí se envía
    final bad = (await queue()).single;
    expect((bad.state, bad.detail), ('rejected', 'Revisa «weight_kg»'));
    await engine.discard(bad);
    expect(await local('2026-10-20'), {'weight_kg': 98.1});
  });

  test('borrar algo que nunca llegó al servidor no le manda nada', () async {
    await engine.put('body_entry', '2026-10-22', {'weight_kg': 97.0});
    await engine.remove('body_entry', '2026-10-22');
    expect(await queue(), isEmpty);
    expect(await db.record('body_entry', '2026-10-22'), isNull);
    await engine.sync();
    expect(server.pushCalls, 0);
  });

  test('borrar sin conexión y el borrado llega al servidor', () async {
    server.edit('body_entry', '2026-10-20', {'weight_kg': 98.1});
    await engine.sync();
    await engine.remove('body_entry', '2026-10-20');
    expect(await db.entityRecords('body_entry'), isEmpty); // ya no se ve
    await engine.sync();
    expect(server.rows[('body_entry', '2026-10-20')]!.deleted, isTrue);
    expect(await db.record('body_entry', '2026-10-20'), isNull);
  });

  test('un envío cortado (app cerrada a medias) se repite sin duplicar', () async {
    await engine.put('body_entry', '2026-10-20', {'weight_kg': 98.1});
    final op = (await queue()).single;
    server.doneOps[op.opId] = await server.push([op]).then((r) => r.single); // el servidor lo aplicó…
    await (db.update(db.outbox)).write(const OutboxCompanion(state: Value('sending'))); // …pero la app no se enteró
    await engine.sync();
    expect(server.rows[('body_entry', '2026-10-20')]!.version, 1);
    expect(await queue(), isEmpty);
  });

  test('la primera descarga quita lo que ya no existe en el servidor', () async {
    await db.upsertRecord(RecordsCompanion.insert(entity: 'body_entry', id: '2020-01-01', data: const Value('{}'), serverVersion: const Value(3)));
    server.edit('body_entry', '2026-10-20', {'weight_kg': 98.1});
    await engine.sync();
    expect((await db.entityRecords('body_entry')).map((r) => r.id), ['2026-10-20']);
  });

  test('al ampliar lo que se sincroniza, la siguiente descarga es completa', () async {
    server.edit('diary_item', 'a', {'date': '2026-10-20', 'meal': 'cena', 'name': 'Viejo', 'kcal': 100}); // ya existía antes
    await db.setMeta('cursor', '${server.log.length}'); // como una base del paso 2: cursor al día
    await db.setMeta('scope', '1');
    await engine.sync();
    expect(decodeData(await db.record('diary_item', 'a'))!['name'], 'Viejo');
    expect(await db.readMeta('scope'), '${SyncEngine.scope}');
  });
}
