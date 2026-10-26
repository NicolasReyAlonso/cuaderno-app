// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
class $RecordsTable extends Records with TableInfo<$RecordsTable, LocalRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
      'entity', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
      'data', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _deletedMeta =
      const VerificationMeta('deleted');
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
      'deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _serverVersionMeta =
      const VerificationMeta('serverVersion');
  @override
  late final GeneratedColumn<int> serverVersion = GeneratedColumn<int>(
      'server_version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _serverDataMeta =
      const VerificationMeta('serverData');
  @override
  late final GeneratedColumn<String> serverData = GeneratedColumn<String>(
      'server_data', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _serverDeletedMeta =
      const VerificationMeta('serverDeleted');
  @override
  late final GeneratedColumn<bool> serverDeleted = GeneratedColumn<bool>(
      'server_deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("server_deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
      'day', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        entity,
        id,
        data,
        deleted,
        serverVersion,
        serverData,
        serverDeleted,
        day
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'records';
  @override
  VerificationContext validateIntegrity(Insertable<LocalRecord> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity')) {
      context.handle(_entityMeta,
          entity.isAcceptableOrUnknown(data['entity']!, _entityMeta));
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
          _dataMeta, this.data.isAcceptableOrUnknown(data['data']!, _dataMeta));
    }
    if (data.containsKey('deleted')) {
      context.handle(_deletedMeta,
          deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta));
    }
    if (data.containsKey('server_version')) {
      context.handle(
          _serverVersionMeta,
          serverVersion.isAcceptableOrUnknown(
              data['server_version']!, _serverVersionMeta));
    }
    if (data.containsKey('server_data')) {
      context.handle(
          _serverDataMeta,
          serverData.isAcceptableOrUnknown(
              data['server_data']!, _serverDataMeta));
    }
    if (data.containsKey('server_deleted')) {
      context.handle(
          _serverDeletedMeta,
          serverDeleted.isAcceptableOrUnknown(
              data['server_deleted']!, _serverDeletedMeta));
    }
    if (data.containsKey('day')) {
      context.handle(
          _dayMeta, day.isAcceptableOrUnknown(data['day']!, _dayMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entity, id};
  @override
  LocalRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRecord(
      entity: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity'])!,
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      data: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}data']),
      deleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}deleted'])!,
      serverVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_version'])!,
      serverData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_data']),
      serverDeleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}server_deleted'])!,
      day: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}day']),
    );
  }

  @override
  $RecordsTable createAlias(String alias) {
    return $RecordsTable(attachedDatabase, alias);
  }
}

class LocalRecord extends DataClass implements Insertable<LocalRecord> {
  final String entity;
  final String id;
  final String? data;
  final bool deleted;
  final int serverVersion;
  final String? serverData;
  final bool serverDeleted;
  final String? day;
  const LocalRecord(
      {required this.entity,
      required this.id,
      this.data,
      required this.deleted,
      required this.serverVersion,
      this.serverData,
      required this.serverDeleted,
      this.day});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity'] = Variable<String>(entity);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || data != null) {
      map['data'] = Variable<String>(data);
    }
    map['deleted'] = Variable<bool>(deleted);
    map['server_version'] = Variable<int>(serverVersion);
    if (!nullToAbsent || serverData != null) {
      map['server_data'] = Variable<String>(serverData);
    }
    map['server_deleted'] = Variable<bool>(serverDeleted);
    if (!nullToAbsent || day != null) {
      map['day'] = Variable<String>(day);
    }
    return map;
  }

  RecordsCompanion toCompanion(bool nullToAbsent) {
    return RecordsCompanion(
      entity: Value(entity),
      id: Value(id),
      data: data == null && nullToAbsent ? const Value.absent() : Value(data),
      deleted: Value(deleted),
      serverVersion: Value(serverVersion),
      serverData: serverData == null && nullToAbsent
          ? const Value.absent()
          : Value(serverData),
      serverDeleted: Value(serverDeleted),
      day: day == null && nullToAbsent ? const Value.absent() : Value(day),
    );
  }

  factory LocalRecord.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRecord(
      entity: serializer.fromJson<String>(json['entity']),
      id: serializer.fromJson<String>(json['id']),
      data: serializer.fromJson<String?>(json['data']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      serverVersion: serializer.fromJson<int>(json['serverVersion']),
      serverData: serializer.fromJson<String?>(json['serverData']),
      serverDeleted: serializer.fromJson<bool>(json['serverDeleted']),
      day: serializer.fromJson<String?>(json['day']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entity': serializer.toJson<String>(entity),
      'id': serializer.toJson<String>(id),
      'data': serializer.toJson<String?>(data),
      'deleted': serializer.toJson<bool>(deleted),
      'serverVersion': serializer.toJson<int>(serverVersion),
      'serverData': serializer.toJson<String?>(serverData),
      'serverDeleted': serializer.toJson<bool>(serverDeleted),
      'day': serializer.toJson<String?>(day),
    };
  }

  LocalRecord copyWith(
          {String? entity,
          String? id,
          Value<String?> data = const Value.absent(),
          bool? deleted,
          int? serverVersion,
          Value<String?> serverData = const Value.absent(),
          bool? serverDeleted,
          Value<String?> day = const Value.absent()}) =>
      LocalRecord(
        entity: entity ?? this.entity,
        id: id ?? this.id,
        data: data.present ? data.value : this.data,
        deleted: deleted ?? this.deleted,
        serverVersion: serverVersion ?? this.serverVersion,
        serverData: serverData.present ? serverData.value : this.serverData,
        serverDeleted: serverDeleted ?? this.serverDeleted,
        day: day.present ? day.value : this.day,
      );
  LocalRecord copyWithCompanion(RecordsCompanion data) {
    return LocalRecord(
      entity: data.entity.present ? data.entity.value : this.entity,
      id: data.id.present ? data.id.value : this.id,
      data: data.data.present ? data.data.value : this.data,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      serverVersion: data.serverVersion.present
          ? data.serverVersion.value
          : this.serverVersion,
      serverData:
          data.serverData.present ? data.serverData.value : this.serverData,
      serverDeleted: data.serverDeleted.present
          ? data.serverDeleted.value
          : this.serverDeleted,
      day: data.day.present ? data.day.value : this.day,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalRecord(')
          ..write('entity: $entity, ')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('deleted: $deleted, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('serverData: $serverData, ')
          ..write('serverDeleted: $serverDeleted, ')
          ..write('day: $day')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      entity, id, data, deleted, serverVersion, serverData, serverDeleted, day);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalRecord &&
          other.entity == this.entity &&
          other.id == this.id &&
          other.data == this.data &&
          other.deleted == this.deleted &&
          other.serverVersion == this.serverVersion &&
          other.serverData == this.serverData &&
          other.serverDeleted == this.serverDeleted &&
          other.day == this.day);
}

class RecordsCompanion extends UpdateCompanion<LocalRecord> {
  final Value<String> entity;
  final Value<String> id;
  final Value<String?> data;
  final Value<bool> deleted;
  final Value<int> serverVersion;
  final Value<String?> serverData;
  final Value<bool> serverDeleted;
  final Value<String?> day;
  final Value<int> rowid;
  const RecordsCompanion({
    this.entity = const Value.absent(),
    this.id = const Value.absent(),
    this.data = const Value.absent(),
    this.deleted = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.serverData = const Value.absent(),
    this.serverDeleted = const Value.absent(),
    this.day = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecordsCompanion.insert({
    required String entity,
    required String id,
    this.data = const Value.absent(),
    this.deleted = const Value.absent(),
    this.serverVersion = const Value.absent(),
    this.serverData = const Value.absent(),
    this.serverDeleted = const Value.absent(),
    this.day = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : entity = Value(entity),
        id = Value(id);
  static Insertable<LocalRecord> custom({
    Expression<String>? entity,
    Expression<String>? id,
    Expression<String>? data,
    Expression<bool>? deleted,
    Expression<int>? serverVersion,
    Expression<String>? serverData,
    Expression<bool>? serverDeleted,
    Expression<String>? day,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entity != null) 'entity': entity,
      if (id != null) 'id': id,
      if (data != null) 'data': data,
      if (deleted != null) 'deleted': deleted,
      if (serverVersion != null) 'server_version': serverVersion,
      if (serverData != null) 'server_data': serverData,
      if (serverDeleted != null) 'server_deleted': serverDeleted,
      if (day != null) 'day': day,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecordsCompanion copyWith(
      {Value<String>? entity,
      Value<String>? id,
      Value<String?>? data,
      Value<bool>? deleted,
      Value<int>? serverVersion,
      Value<String?>? serverData,
      Value<bool>? serverDeleted,
      Value<String?>? day,
      Value<int>? rowid}) {
    return RecordsCompanion(
      entity: entity ?? this.entity,
      id: id ?? this.id,
      data: data ?? this.data,
      deleted: deleted ?? this.deleted,
      serverVersion: serverVersion ?? this.serverVersion,
      serverData: serverData ?? this.serverData,
      serverDeleted: serverDeleted ?? this.serverDeleted,
      day: day ?? this.day,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (serverVersion.present) {
      map['server_version'] = Variable<int>(serverVersion.value);
    }
    if (serverData.present) {
      map['server_data'] = Variable<String>(serverData.value);
    }
    if (serverDeleted.present) {
      map['server_deleted'] = Variable<bool>(serverDeleted.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordsCompanion(')
          ..write('entity: $entity, ')
          ..write('id: $id, ')
          ..write('data: $data, ')
          ..write('deleted: $deleted, ')
          ..write('serverVersion: $serverVersion, ')
          ..write('serverData: $serverData, ')
          ..write('serverDeleted: $serverDeleted, ')
          ..write('day: $day, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxOp> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
      'seq', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _opIdMeta = const VerificationMeta('opId');
  @override
  late final GeneratedColumn<String> opId = GeneratedColumn<String>(
      'op_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
      'entity', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'record_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _baseVersionMeta =
      const VerificationMeta('baseVersion');
  @override
  late final GeneratedColumn<int> baseVersion = GeneratedColumn<int>(
      'base_version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
      'data', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isDeleteMeta =
      const VerificationMeta('isDelete');
  @override
  late final GeneratedColumn<bool> isDelete = GeneratedColumn<bool>(
      'is_delete', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_delete" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
      'state', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _serverRecordMeta =
      const VerificationMeta('serverRecord');
  @override
  late final GeneratedColumn<String> serverRecord = GeneratedColumn<String>(
      'server_record', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
      'detail', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        seq,
        opId,
        entity,
        recordId,
        baseVersion,
        data,
        isDelete,
        state,
        serverRecord,
        detail,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(Insertable<OutboxOp> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('seq')) {
      context.handle(
          _seqMeta, seq.isAcceptableOrUnknown(data['seq']!, _seqMeta));
    }
    if (data.containsKey('op_id')) {
      context.handle(
          _opIdMeta, opId.isAcceptableOrUnknown(data['op_id']!, _opIdMeta));
    } else if (isInserting) {
      context.missing(_opIdMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(_entityMeta,
          entity.isAcceptableOrUnknown(data['entity']!, _entityMeta));
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta));
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('base_version')) {
      context.handle(
          _baseVersionMeta,
          baseVersion.isAcceptableOrUnknown(
              data['base_version']!, _baseVersionMeta));
    } else if (isInserting) {
      context.missing(_baseVersionMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
          _dataMeta, this.data.isAcceptableOrUnknown(data['data']!, _dataMeta));
    }
    if (data.containsKey('is_delete')) {
      context.handle(_isDeleteMeta,
          isDelete.isAcceptableOrUnknown(data['is_delete']!, _isDeleteMeta));
    }
    if (data.containsKey('state')) {
      context.handle(
          _stateMeta, state.isAcceptableOrUnknown(data['state']!, _stateMeta));
    }
    if (data.containsKey('server_record')) {
      context.handle(
          _serverRecordMeta,
          serverRecord.isAcceptableOrUnknown(
              data['server_record']!, _serverRecordMeta));
    }
    if (data.containsKey('detail')) {
      context.handle(_detailMeta,
          detail.isAcceptableOrUnknown(data['detail']!, _detailMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seq};
  @override
  OutboxOp map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxOp(
      seq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}seq'])!,
      opId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}op_id'])!,
      entity: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_id'])!,
      baseVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}base_version'])!,
      data: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}data']),
      isDelete: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_delete'])!,
      state: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!,
      serverRecord: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_record']),
      detail: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}detail']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxOp extends DataClass implements Insertable<OutboxOp> {
  final int seq;
  final String opId;
  final String entity;
  final String recordId;
  final int baseVersion;
  final String? data;
  final bool isDelete;
  final String state;
  final String? serverRecord;
  final String? detail;
  final DateTime createdAt;
  const OutboxOp(
      {required this.seq,
      required this.opId,
      required this.entity,
      required this.recordId,
      required this.baseVersion,
      this.data,
      required this.isDelete,
      required this.state,
      this.serverRecord,
      this.detail,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['seq'] = Variable<int>(seq);
    map['op_id'] = Variable<String>(opId);
    map['entity'] = Variable<String>(entity);
    map['record_id'] = Variable<String>(recordId);
    map['base_version'] = Variable<int>(baseVersion);
    if (!nullToAbsent || data != null) {
      map['data'] = Variable<String>(data);
    }
    map['is_delete'] = Variable<bool>(isDelete);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || serverRecord != null) {
      map['server_record'] = Variable<String>(serverRecord);
    }
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      seq: Value(seq),
      opId: Value(opId),
      entity: Value(entity),
      recordId: Value(recordId),
      baseVersion: Value(baseVersion),
      data: data == null && nullToAbsent ? const Value.absent() : Value(data),
      isDelete: Value(isDelete),
      state: Value(state),
      serverRecord: serverRecord == null && nullToAbsent
          ? const Value.absent()
          : Value(serverRecord),
      detail:
          detail == null && nullToAbsent ? const Value.absent() : Value(detail),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxOp.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxOp(
      seq: serializer.fromJson<int>(json['seq']),
      opId: serializer.fromJson<String>(json['opId']),
      entity: serializer.fromJson<String>(json['entity']),
      recordId: serializer.fromJson<String>(json['recordId']),
      baseVersion: serializer.fromJson<int>(json['baseVersion']),
      data: serializer.fromJson<String?>(json['data']),
      isDelete: serializer.fromJson<bool>(json['isDelete']),
      state: serializer.fromJson<String>(json['state']),
      serverRecord: serializer.fromJson<String?>(json['serverRecord']),
      detail: serializer.fromJson<String?>(json['detail']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seq': serializer.toJson<int>(seq),
      'opId': serializer.toJson<String>(opId),
      'entity': serializer.toJson<String>(entity),
      'recordId': serializer.toJson<String>(recordId),
      'baseVersion': serializer.toJson<int>(baseVersion),
      'data': serializer.toJson<String?>(data),
      'isDelete': serializer.toJson<bool>(isDelete),
      'state': serializer.toJson<String>(state),
      'serverRecord': serializer.toJson<String?>(serverRecord),
      'detail': serializer.toJson<String?>(detail),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OutboxOp copyWith(
          {int? seq,
          String? opId,
          String? entity,
          String? recordId,
          int? baseVersion,
          Value<String?> data = const Value.absent(),
          bool? isDelete,
          String? state,
          Value<String?> serverRecord = const Value.absent(),
          Value<String?> detail = const Value.absent(),
          DateTime? createdAt}) =>
      OutboxOp(
        seq: seq ?? this.seq,
        opId: opId ?? this.opId,
        entity: entity ?? this.entity,
        recordId: recordId ?? this.recordId,
        baseVersion: baseVersion ?? this.baseVersion,
        data: data.present ? data.value : this.data,
        isDelete: isDelete ?? this.isDelete,
        state: state ?? this.state,
        serverRecord:
            serverRecord.present ? serverRecord.value : this.serverRecord,
        detail: detail.present ? detail.value : this.detail,
        createdAt: createdAt ?? this.createdAt,
      );
  OutboxOp copyWithCompanion(OutboxCompanion data) {
    return OutboxOp(
      seq: data.seq.present ? data.seq.value : this.seq,
      opId: data.opId.present ? data.opId.value : this.opId,
      entity: data.entity.present ? data.entity.value : this.entity,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      baseVersion:
          data.baseVersion.present ? data.baseVersion.value : this.baseVersion,
      data: data.data.present ? data.data.value : this.data,
      isDelete: data.isDelete.present ? data.isDelete.value : this.isDelete,
      state: data.state.present ? data.state.value : this.state,
      serverRecord: data.serverRecord.present
          ? data.serverRecord.value
          : this.serverRecord,
      detail: data.detail.present ? data.detail.value : this.detail,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxOp(')
          ..write('seq: $seq, ')
          ..write('opId: $opId, ')
          ..write('entity: $entity, ')
          ..write('recordId: $recordId, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('data: $data, ')
          ..write('isDelete: $isDelete, ')
          ..write('state: $state, ')
          ..write('serverRecord: $serverRecord, ')
          ..write('detail: $detail, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(seq, opId, entity, recordId, baseVersion,
      data, isDelete, state, serverRecord, detail, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxOp &&
          other.seq == this.seq &&
          other.opId == this.opId &&
          other.entity == this.entity &&
          other.recordId == this.recordId &&
          other.baseVersion == this.baseVersion &&
          other.data == this.data &&
          other.isDelete == this.isDelete &&
          other.state == this.state &&
          other.serverRecord == this.serverRecord &&
          other.detail == this.detail &&
          other.createdAt == this.createdAt);
}

class OutboxCompanion extends UpdateCompanion<OutboxOp> {
  final Value<int> seq;
  final Value<String> opId;
  final Value<String> entity;
  final Value<String> recordId;
  final Value<int> baseVersion;
  final Value<String?> data;
  final Value<bool> isDelete;
  final Value<String> state;
  final Value<String?> serverRecord;
  final Value<String?> detail;
  final Value<DateTime> createdAt;
  const OutboxCompanion({
    this.seq = const Value.absent(),
    this.opId = const Value.absent(),
    this.entity = const Value.absent(),
    this.recordId = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.data = const Value.absent(),
    this.isDelete = const Value.absent(),
    this.state = const Value.absent(),
    this.serverRecord = const Value.absent(),
    this.detail = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.seq = const Value.absent(),
    required String opId,
    required String entity,
    required String recordId,
    required int baseVersion,
    this.data = const Value.absent(),
    this.isDelete = const Value.absent(),
    this.state = const Value.absent(),
    this.serverRecord = const Value.absent(),
    this.detail = const Value.absent(),
    this.createdAt = const Value.absent(),
  })  : opId = Value(opId),
        entity = Value(entity),
        recordId = Value(recordId),
        baseVersion = Value(baseVersion);
  static Insertable<OutboxOp> custom({
    Expression<int>? seq,
    Expression<String>? opId,
    Expression<String>? entity,
    Expression<String>? recordId,
    Expression<int>? baseVersion,
    Expression<String>? data,
    Expression<bool>? isDelete,
    Expression<String>? state,
    Expression<String>? serverRecord,
    Expression<String>? detail,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (seq != null) 'seq': seq,
      if (opId != null) 'op_id': opId,
      if (entity != null) 'entity': entity,
      if (recordId != null) 'record_id': recordId,
      if (baseVersion != null) 'base_version': baseVersion,
      if (data != null) 'data': data,
      if (isDelete != null) 'is_delete': isDelete,
      if (state != null) 'state': state,
      if (serverRecord != null) 'server_record': serverRecord,
      if (detail != null) 'detail': detail,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  OutboxCompanion copyWith(
      {Value<int>? seq,
      Value<String>? opId,
      Value<String>? entity,
      Value<String>? recordId,
      Value<int>? baseVersion,
      Value<String?>? data,
      Value<bool>? isDelete,
      Value<String>? state,
      Value<String?>? serverRecord,
      Value<String?>? detail,
      Value<DateTime>? createdAt}) {
    return OutboxCompanion(
      seq: seq ?? this.seq,
      opId: opId ?? this.opId,
      entity: entity ?? this.entity,
      recordId: recordId ?? this.recordId,
      baseVersion: baseVersion ?? this.baseVersion,
      data: data ?? this.data,
      isDelete: isDelete ?? this.isDelete,
      state: state ?? this.state,
      serverRecord: serverRecord ?? this.serverRecord,
      detail: detail ?? this.detail,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (opId.present) {
      map['op_id'] = Variable<String>(opId.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (baseVersion.present) {
      map['base_version'] = Variable<int>(baseVersion.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (isDelete.present) {
      map['is_delete'] = Variable<bool>(isDelete.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (serverRecord.present) {
      map['server_record'] = Variable<String>(serverRecord.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('seq: $seq, ')
          ..write('opId: $opId, ')
          ..write('entity: $entity, ')
          ..write('recordId: $recordId, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('data: $data, ')
          ..write('isDelete: $isDelete, ')
          ..write('state: $state, ')
          ..write('serverRecord: $serverRecord, ')
          ..write('detail: $detail, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $MetaTable extends Meta with TableInfo<$MetaTable, MetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meta';
  @override
  VerificationContext validateIntegrity(Insertable<MetaData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  MetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetaData(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $MetaTable createAlias(String alias) {
    return $MetaTable(attachedDatabase, alias);
  }
}

class MetaData extends DataClass implements Insertable<MetaData> {
  final String key;
  final String value;
  const MetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  MetaCompanion toCompanion(bool nullToAbsent) {
    return MetaCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory MetaData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  MetaData copyWith({String? key, String? value}) => MetaData(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  MetaData copyWithCompanion(MetaCompanion data) {
    return MetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaData && other.key == this.key && other.value == this.value);
}

class MetaCompanion extends UpdateCompanion<MetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const MetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<MetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetaCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return MetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDb extends GeneratedDatabase {
  _$LocalDb(QueryExecutor e) : super(e);
  $LocalDbManager get managers => $LocalDbManager(this);
  late final $RecordsTable records = $RecordsTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $MetaTable meta = $MetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [records, outbox, meta];
}

typedef $$RecordsTableCreateCompanionBuilder = RecordsCompanion Function({
  required String entity,
  required String id,
  Value<String?> data,
  Value<bool> deleted,
  Value<int> serverVersion,
  Value<String?> serverData,
  Value<bool> serverDeleted,
  Value<String?> day,
  Value<int> rowid,
});
typedef $$RecordsTableUpdateCompanionBuilder = RecordsCompanion Function({
  Value<String> entity,
  Value<String> id,
  Value<String?> data,
  Value<bool> deleted,
  Value<int> serverVersion,
  Value<String?> serverData,
  Value<bool> serverDeleted,
  Value<String?> day,
  Value<int> rowid,
});

class $$RecordsTableFilterComposer extends Composer<_$LocalDb, $RecordsTable> {
  $$RecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get deleted => $composableBuilder(
      column: $table.deleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverData => $composableBuilder(
      column: $table.serverData, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get serverDeleted => $composableBuilder(
      column: $table.serverDeleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get day => $composableBuilder(
      column: $table.day, builder: (column) => ColumnFilters(column));
}

class $$RecordsTableOrderingComposer
    extends Composer<_$LocalDb, $RecordsTable> {
  $$RecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get deleted => $composableBuilder(
      column: $table.deleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverData => $composableBuilder(
      column: $table.serverData, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get serverDeleted => $composableBuilder(
      column: $table.serverDeleted,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get day => $composableBuilder(
      column: $table.day, builder: (column) => ColumnOrderings(column));
}

class $$RecordsTableAnnotationComposer
    extends Composer<_$LocalDb, $RecordsTable> {
  $$RecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<int> get serverVersion => $composableBuilder(
      column: $table.serverVersion, builder: (column) => column);

  GeneratedColumn<String> get serverData => $composableBuilder(
      column: $table.serverData, builder: (column) => column);

  GeneratedColumn<bool> get serverDeleted => $composableBuilder(
      column: $table.serverDeleted, builder: (column) => column);

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);
}

class $$RecordsTableTableManager extends RootTableManager<
    _$LocalDb,
    $RecordsTable,
    LocalRecord,
    $$RecordsTableFilterComposer,
    $$RecordsTableOrderingComposer,
    $$RecordsTableAnnotationComposer,
    $$RecordsTableCreateCompanionBuilder,
    $$RecordsTableUpdateCompanionBuilder,
    (LocalRecord, BaseReferences<_$LocalDb, $RecordsTable, LocalRecord>),
    LocalRecord,
    PrefetchHooks Function()> {
  $$RecordsTableTableManager(_$LocalDb db, $RecordsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> entity = const Value.absent(),
            Value<String> id = const Value.absent(),
            Value<String?> data = const Value.absent(),
            Value<bool> deleted = const Value.absent(),
            Value<int> serverVersion = const Value.absent(),
            Value<String?> serverData = const Value.absent(),
            Value<bool> serverDeleted = const Value.absent(),
            Value<String?> day = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RecordsCompanion(
            entity: entity,
            id: id,
            data: data,
            deleted: deleted,
            serverVersion: serverVersion,
            serverData: serverData,
            serverDeleted: serverDeleted,
            day: day,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String entity,
            required String id,
            Value<String?> data = const Value.absent(),
            Value<bool> deleted = const Value.absent(),
            Value<int> serverVersion = const Value.absent(),
            Value<String?> serverData = const Value.absent(),
            Value<bool> serverDeleted = const Value.absent(),
            Value<String?> day = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RecordsCompanion.insert(
            entity: entity,
            id: id,
            data: data,
            deleted: deleted,
            serverVersion: serverVersion,
            serverData: serverData,
            serverDeleted: serverDeleted,
            day: day,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$RecordsTable, LocalRecord>(table),
                    BaseReferences<_$LocalDb, $RecordsTable, LocalRecord>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RecordsTableProcessedTableManager = ProcessedTableManager<
    _$LocalDb,
    $RecordsTable,
    LocalRecord,
    $$RecordsTableFilterComposer,
    $$RecordsTableOrderingComposer,
    $$RecordsTableAnnotationComposer,
    $$RecordsTableCreateCompanionBuilder,
    $$RecordsTableUpdateCompanionBuilder,
    (LocalRecord, BaseReferences<_$LocalDb, $RecordsTable, LocalRecord>),
    LocalRecord,
    PrefetchHooks Function()>;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  Value<int> seq,
  required String opId,
  required String entity,
  required String recordId,
  required int baseVersion,
  Value<String?> data,
  Value<bool> isDelete,
  Value<String> state,
  Value<String?> serverRecord,
  Value<String?> detail,
  Value<DateTime> createdAt,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<int> seq,
  Value<String> opId,
  Value<String> entity,
  Value<String> recordId,
  Value<int> baseVersion,
  Value<String?> data,
  Value<bool> isDelete,
  Value<String> state,
  Value<String?> serverRecord,
  Value<String?> detail,
  Value<DateTime> createdAt,
});

class $$OutboxTableFilterComposer extends Composer<_$LocalDb, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get opId => $composableBuilder(
      column: $table.opId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get baseVersion => $composableBuilder(
      column: $table.baseVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDelete => $composableBuilder(
      column: $table.isDelete, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverRecord => $composableBuilder(
      column: $table.serverRecord, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get detail => $composableBuilder(
      column: $table.detail, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$OutboxTableOrderingComposer extends Composer<_$LocalDb, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seq => $composableBuilder(
      column: $table.seq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get opId => $composableBuilder(
      column: $table.opId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get baseVersion => $composableBuilder(
      column: $table.baseVersion, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDelete => $composableBuilder(
      column: $table.isDelete, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverRecord => $composableBuilder(
      column: $table.serverRecord,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get detail => $composableBuilder(
      column: $table.detail, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$LocalDb, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get opId =>
      $composableBuilder(column: $table.opId, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<int> get baseVersion => $composableBuilder(
      column: $table.baseVersion, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<bool> get isDelete =>
      $composableBuilder(column: $table.isDelete, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get serverRecord => $composableBuilder(
      column: $table.serverRecord, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OutboxTableTableManager extends RootTableManager<
    _$LocalDb,
    $OutboxTable,
    OutboxOp,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxOp, BaseReferences<_$LocalDb, $OutboxTable, OutboxOp>),
    OutboxOp,
    PrefetchHooks Function()> {
  $$OutboxTableTableManager(_$LocalDb db, $OutboxTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> seq = const Value.absent(),
            Value<String> opId = const Value.absent(),
            Value<String> entity = const Value.absent(),
            Value<String> recordId = const Value.absent(),
            Value<int> baseVersion = const Value.absent(),
            Value<String?> data = const Value.absent(),
            Value<bool> isDelete = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<String?> serverRecord = const Value.absent(),
            Value<String?> detail = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              OutboxCompanion(
            seq: seq,
            opId: opId,
            entity: entity,
            recordId: recordId,
            baseVersion: baseVersion,
            data: data,
            isDelete: isDelete,
            state: state,
            serverRecord: serverRecord,
            detail: detail,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> seq = const Value.absent(),
            required String opId,
            required String entity,
            required String recordId,
            required int baseVersion,
            Value<String?> data = const Value.absent(),
            Value<bool> isDelete = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<String?> serverRecord = const Value.absent(),
            Value<String?> detail = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              OutboxCompanion.insert(
            seq: seq,
            opId: opId,
            entity: entity,
            recordId: recordId,
            baseVersion: baseVersion,
            data: data,
            isDelete: isDelete,
            state: state,
            serverRecord: serverRecord,
            detail: detail,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$OutboxTable, OutboxOp>(table),
                    BaseReferences<_$LocalDb, $OutboxTable, OutboxOp>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OutboxTableProcessedTableManager = ProcessedTableManager<
    _$LocalDb,
    $OutboxTable,
    OutboxOp,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxOp, BaseReferences<_$LocalDb, $OutboxTable, OutboxOp>),
    OutboxOp,
    PrefetchHooks Function()>;
typedef $$MetaTableCreateCompanionBuilder = MetaCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$MetaTableUpdateCompanionBuilder = MetaCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$MetaTableFilterComposer extends Composer<_$LocalDb, $MetaTable> {
  $$MetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$MetaTableOrderingComposer extends Composer<_$LocalDb, $MetaTable> {
  $$MetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$MetaTableAnnotationComposer extends Composer<_$LocalDb, $MetaTable> {
  $$MetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$MetaTableTableManager extends RootTableManager<
    _$LocalDb,
    $MetaTable,
    MetaData,
    $$MetaTableFilterComposer,
    $$MetaTableOrderingComposer,
    $$MetaTableAnnotationComposer,
    $$MetaTableCreateCompanionBuilder,
    $$MetaTableUpdateCompanionBuilder,
    (MetaData, BaseReferences<_$LocalDb, $MetaTable, MetaData>),
    MetaData,
    PrefetchHooks Function()> {
  $$MetaTableTableManager(_$LocalDb db, $MetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MetaCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              MetaCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$MetaTable, MetaData>(table),
                    BaseReferences<_$LocalDb, $MetaTable, MetaData>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MetaTableProcessedTableManager = ProcessedTableManager<
    _$LocalDb,
    $MetaTable,
    MetaData,
    $$MetaTableFilterComposer,
    $$MetaTableOrderingComposer,
    $$MetaTableAnnotationComposer,
    $$MetaTableCreateCompanionBuilder,
    $$MetaTableUpdateCompanionBuilder,
    (MetaData, BaseReferences<_$LocalDb, $MetaTable, MetaData>),
    MetaData,
    PrefetchHooks Function()>;

class $LocalDbManager {
  final _$LocalDb _db;
  $LocalDbManager(this._db);
  $$RecordsTableTableManager get records =>
      $$RecordsTableTableManager(_db, _db.records);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$MetaTableTableManager get meta => $$MetaTableTableManager(_db, _db.meta);
}
