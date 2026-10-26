import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_db.g.dart';

/// Copia local de los registros sincronizados (perfil, Peso, pulsera…), de cualquier tipo.
///
/// Cada fila guarda lo que ve el usuario (data / deleted) y lo último que se sabe del
/// servidor (serverVersion / serverData / serverDeleted): volver a esto último es como se
/// descarta un cambio o se elige «lo del servidor» en un conflicto.
@DataClassName('LocalRecord')
class Records extends Table {
  TextColumn get entity => text()();
  TextColumn get id => text()();
  TextColumn get data => text().nullable()(); // JSON; null si está borrado
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  IntColumn get serverVersion => integer().withDefault(const Constant(0))(); // 0 = el servidor no lo tiene
  TextColumn get serverData => text().nullable()();
  BoolColumn get serverDeleted => boolean().withDefault(const Constant(false))();
  // Fecha del registro (AAAA-MM-DD) si su JSON la trae: para pedir «lo del día X» sin leerlo todo
  TextColumn get day => text().nullable()();

  @override
  Set<Column> get primaryKey => {entity, id};

}

/// Cambios hechos en la app que aún no ha confirmado el servidor, en orden.
/// state: pending | sending | conflict | rejected.
@DataClassName('OutboxOp')
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get opId => text()();
  TextColumn get entity => text()();
  TextColumn get recordId => text()();
  IntColumn get baseVersion => integer()();
  TextColumn get data => text().nullable()();
  BoolColumn get isDelete => boolean().withDefault(const Constant(false))();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  TextColumn get serverRecord => text().nullable()(); // en conflicto: lo que hay en el servidor (JSON de SyncRecord)
  TextColumn get detail => text().nullable()(); // en rechazo: por qué
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Valores sueltos: cursor de sincronización, usuario de la base…
class Meta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Records, Outbox, Meta])
class LocalDb extends _$LocalDb {
  LocalDb(super.e);

  /// La base del dispositivo. En web necesita web/sqlite3.wasm y web/drift_worker.js.
  LocalDb.open()
      : super(driftDatabase(
          name: 'cuaderno',
          web: DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js')),
        ));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX IF NOT EXISTS records_entity_day ON records (entity, day)');
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: columna day (Comidas sin conexión). Se rellena con la fecha de lo que ya había.
            await m.addColumn(records, records.day);
            await customStatement("UPDATE records SET day = json_extract(data, '\$.date') WHERE data IS NOT NULL");
            await customStatement('CREATE INDEX IF NOT EXISTS records_entity_day ON records (entity, day)');
          }
        },
      );

  // ---------------------------------------------------------------- registros
  Future<LocalRecord?> record(String entity, String id) =>
      (select(records)..where((r) => r.entity.equals(entity) & r.id.equals(id))).getSingleOrNull();

  /// Registros visibles (no borrados) de un tipo, en vivo: la pantalla se actualiza sola.
  Stream<List<LocalRecord>> watchEntity(String entity) =>
      (select(records)..where((r) => r.entity.equals(entity) & r.deleted.not())..orderBy([(r) => OrderingTerm(expression: r.id)])).watch();

  /// Registros visibles de un tipo en un día (p. ej. el diario de Comidas), en vivo.
  Stream<List<LocalRecord>> watchDay(String entity, String day) =>
      (select(records)..where((r) => r.entity.equals(entity) & r.day.equals(day) & r.deleted.not())).watch();

  /// Suma por día de dos campos numéricos del JSON (kcal y proteína del diario para Peso), en vivo.
  Stream<Map<String, ({double a, double b})>> watchDailySums(String entity, String fieldA, String fieldB) => customSelect(
        "SELECT day, SUM(json_extract(data, '\$.$fieldA')) AS a, SUM(json_extract(data, '\$.$fieldB')) AS b "
        'FROM records WHERE entity = ? AND deleted = 0 AND day IS NOT NULL GROUP BY day',
        variables: [Variable.withString(entity)],
        readsFrom: {records},
      ).watch().map((rows) => {
            // SUM devuelve entero o real según los datos: se lee tal cual y se pasa a double
            for (final r in rows) r.read<String>('day'): (a: ((r.data['a'] as num?) ?? 0).toDouble(), b: ((r.data['b'] as num?) ?? 0).toDouble()),
          });

  Future<List<LocalRecord>> entityRecords(String entity) =>
      (select(records)..where((r) => r.entity.equals(entity) & r.deleted.not())).get();

  Future<void> upsertRecord(RecordsCompanion r) => into(records).insertOnConflictUpdate(r);

  Future<void> removeRecord(String entity, String id) => (delete(records)..where((r) => r.entity.equals(entity) & r.id.equals(id))).go();

  // ---------------------------------------------------------------- cola
  Future<List<OutboxOp>> opsOf(String entity, String id) =>
      (select(outbox)..where((o) => o.entity.equals(entity) & o.recordId.equals(id))..orderBy([(o) => OrderingTerm(expression: o.seq)])).get();

  Future<OutboxOp?> op(String opId) => (select(outbox)..where((o) => o.opId.equals(opId))).getSingleOrNull();

  Stream<List<OutboxOp>> watchOutbox() => (select(outbox)..orderBy([(o) => OrderingTerm(expression: o.seq)])).watch();

  // ---------------------------------------------------------------- meta
  Future<String?> readMeta(String key) async => (await (select(meta)..where((m) => m.key.equals(key))).getSingleOrNull())?.value;

  Stream<String?> watchMeta(String key) => (select(meta)..where((m) => m.key.equals(key))).watchSingleOrNull().map((m) => m?.value);

  Future<void> setMeta(String key, String value) => into(meta).insertOnConflictUpdate(MetaCompanion.insert(key: key, value: value));

  /// Al cerrar sesión: otra cuenta no debe ver nada de esta.
  Future<void> wipe() => transaction(() async {
        await delete(records).go();
        await delete(outbox).go();
        await delete(meta).go();
      });
}

/// La fecha que lleva el JSON de un registro (campo «date»), para la columna day.
String? dayOf(Map<String, dynamic>? data) {
  final d = data?['date'];
  return d is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d) ? d : null;
}

Map<String, dynamic>? decode(String? json) => json == null ? null : jsonDecode(json) as Map<String, dynamic>;

/// Datos visibles de un registro local (null si no existe o está borrado).
Map<String, dynamic>? decodeData(LocalRecord? r) => r == null || r.deleted ? null : decode(r.data);
