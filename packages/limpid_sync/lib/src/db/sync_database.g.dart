// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_database.dart';

// ignore_for_file: type=lint
class $OpQueueRowsTable extends OpQueueRows
    with TableInfo<$OpQueueRowsTable, OpQueueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OpQueueRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationKeyMeta = const VerificationMeta(
    'operationKey',
  );
  @override
  late final GeneratedColumn<String> operationKey = GeneratedColumn<String>(
    'operation_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lamportMeta = const VerificationMeta(
    'lamport',
  );
  @override
  late final GeneratedColumn<int> lamport = GeneratedColumn<int>(
    'lamport',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorIdMeta = const VerificationMeta(
    'authorId',
  );
  @override
  late final GeneratedColumn<String> authorId = GeneratedColumn<String>(
    'author_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<int> lastAttemptAt = GeneratedColumn<int>(
    'last_attempt_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<int> nextAttemptAt = GeneratedColumn<int>(
    'next_attempt_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationKey,
    documentId,
    lamport,
    authorId,
    status,
    attempts,
    payload,
    createdAt,
    lastAttemptAt,
    nextAttemptAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'op_queue_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<OpQueueEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_key')) {
      context.handle(
        _operationKeyMeta,
        operationKey.isAcceptableOrUnknown(
          data['operation_key']!,
          _operationKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationKeyMeta);
    }
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('lamport')) {
      context.handle(
        _lamportMeta,
        lamport.isAcceptableOrUnknown(data['lamport']!, _lamportMeta),
      );
    } else if (isInserting) {
      context.missing(_lamportMeta);
    }
    if (data.containsKey('author_id')) {
      context.handle(
        _authorIdMeta,
        authorId.isAcceptableOrUnknown(data['author_id']!, _authorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_authorIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationKey};
  @override
  OpQueueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OpQueueEntry(
      operationKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_key'],
      )!,
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      )!,
      lamport: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lamport'],
      )!,
      authorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_attempt_at'],
      ),
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $OpQueueRowsTable createAlias(String alias) {
    return $OpQueueRowsTable(attachedDatabase, alias);
  }
}

class OpQueueEntry extends DataClass implements Insertable<OpQueueEntry> {
  /// The identity of the operation, `(doc_id, lamport, author_id)`.
  final String operationKey;

  /// The document the operation belongs to.
  final String documentId;

  /// The Lamport timestamp of the operation.
  final int lamport;

  /// The author of the operation.
  final String authorId;

  /// The state of the entry: `pending`, `sent` or `failed`.
  final String status;

  /// The number of attempts already made.
  final int attempts;

  /// The encoded operation, in the wire format of the API.
  final String payload;

  /// The moment the operation entered the queue, in milliseconds.
  final int createdAt;

  /// The moment of the last attempt, in milliseconds.
  final int? lastAttemptAt;

  /// The earliest moment of the next attempt, in milliseconds.
  final int? nextAttemptAt;

  /// The reason of the last failure.
  final String? lastError;
  const OpQueueEntry({
    required this.operationKey,
    required this.documentId,
    required this.lamport,
    required this.authorId,
    required this.status,
    required this.attempts,
    required this.payload,
    required this.createdAt,
    this.lastAttemptAt,
    this.nextAttemptAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_key'] = Variable<String>(operationKey);
    map['document_id'] = Variable<String>(documentId);
    map['lamport'] = Variable<int>(lamport);
    map['author_id'] = Variable<String>(authorId);
    map['status'] = Variable<String>(status);
    map['attempts'] = Variable<int>(attempts);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<int>(lastAttemptAt);
    }
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OpQueueRowsCompanion toCompanion(bool nullToAbsent) {
    return OpQueueRowsCompanion(
      operationKey: Value(operationKey),
      documentId: Value(documentId),
      lamport: Value(lamport),
      authorId: Value(authorId),
      status: Value(status),
      attempts: Value(attempts),
      payload: Value(payload),
      createdAt: Value(createdAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OpQueueEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OpQueueEntry(
      operationKey: serializer.fromJson<String>(json['operationKey']),
      documentId: serializer.fromJson<String>(json['documentId']),
      lamport: serializer.fromJson<int>(json['lamport']),
      authorId: serializer.fromJson<String>(json['authorId']),
      status: serializer.fromJson<String>(json['status']),
      attempts: serializer.fromJson<int>(json['attempts']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      lastAttemptAt: serializer.fromJson<int?>(json['lastAttemptAt']),
      nextAttemptAt: serializer.fromJson<int?>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationKey': serializer.toJson<String>(operationKey),
      'documentId': serializer.toJson<String>(documentId),
      'lamport': serializer.toJson<int>(lamport),
      'authorId': serializer.toJson<String>(authorId),
      'status': serializer.toJson<String>(status),
      'attempts': serializer.toJson<int>(attempts),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<int>(createdAt),
      'lastAttemptAt': serializer.toJson<int?>(lastAttemptAt),
      'nextAttemptAt': serializer.toJson<int?>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OpQueueEntry copyWith({
    String? operationKey,
    String? documentId,
    int? lamport,
    String? authorId,
    String? status,
    int? attempts,
    String? payload,
    int? createdAt,
    Value<int?> lastAttemptAt = const Value.absent(),
    Value<int?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) => OpQueueEntry(
    operationKey: operationKey ?? this.operationKey,
    documentId: documentId ?? this.documentId,
    lamport: lamport ?? this.lamport,
    authorId: authorId ?? this.authorId,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  OpQueueEntry copyWithCompanion(OpQueueRowsCompanion data) {
    return OpQueueEntry(
      operationKey: data.operationKey.present
          ? data.operationKey.value
          : this.operationKey,
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      lamport: data.lamport.present ? data.lamport.value : this.lamport,
      authorId: data.authorId.present ? data.authorId.value : this.authorId,
      status: data.status.present ? data.status.value : this.status,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OpQueueEntry(')
          ..write('operationKey: $operationKey, ')
          ..write('documentId: $documentId, ')
          ..write('lamport: $lamport, ')
          ..write('authorId: $authorId, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationKey,
    documentId,
    lamport,
    authorId,
    status,
    attempts,
    payload,
    createdAt,
    lastAttemptAt,
    nextAttemptAt,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OpQueueEntry &&
          other.operationKey == this.operationKey &&
          other.documentId == this.documentId &&
          other.lamport == this.lamport &&
          other.authorId == this.authorId &&
          other.status == this.status &&
          other.attempts == this.attempts &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError);
}

class OpQueueRowsCompanion extends UpdateCompanion<OpQueueEntry> {
  final Value<String> operationKey;
  final Value<String> documentId;
  final Value<int> lamport;
  final Value<String> authorId;
  final Value<String> status;
  final Value<int> attempts;
  final Value<String> payload;
  final Value<int> createdAt;
  final Value<int?> lastAttemptAt;
  final Value<int?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<int> rowid;
  const OpQueueRowsCompanion({
    this.operationKey = const Value.absent(),
    this.documentId = const Value.absent(),
    this.lamport = const Value.absent(),
    this.authorId = const Value.absent(),
    this.status = const Value.absent(),
    this.attempts = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OpQueueRowsCompanion.insert({
    required String operationKey,
    required String documentId,
    required int lamport,
    required String authorId,
    required String status,
    this.attempts = const Value.absent(),
    required String payload,
    required int createdAt,
    this.lastAttemptAt = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : operationKey = Value(operationKey),
       documentId = Value(documentId),
       lamport = Value(lamport),
       authorId = Value(authorId),
       status = Value(status),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<OpQueueEntry> custom({
    Expression<String>? operationKey,
    Expression<String>? documentId,
    Expression<int>? lamport,
    Expression<String>? authorId,
    Expression<String>? status,
    Expression<int>? attempts,
    Expression<String>? payload,
    Expression<int>? createdAt,
    Expression<int>? lastAttemptAt,
    Expression<int>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationKey != null) 'operation_key': operationKey,
      if (documentId != null) 'document_id': documentId,
      if (lamport != null) 'lamport': lamport,
      if (authorId != null) 'author_id': authorId,
      if (status != null) 'status': status,
      if (attempts != null) 'attempts': attempts,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OpQueueRowsCompanion copyWith({
    Value<String>? operationKey,
    Value<String>? documentId,
    Value<int>? lamport,
    Value<String>? authorId,
    Value<String>? status,
    Value<int>? attempts,
    Value<String>? payload,
    Value<int>? createdAt,
    Value<int?>? lastAttemptAt,
    Value<int?>? nextAttemptAt,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return OpQueueRowsCompanion(
      operationKey: operationKey ?? this.operationKey,
      documentId: documentId ?? this.documentId,
      lamport: lamport ?? this.lamport,
      authorId: authorId ?? this.authorId,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationKey.present) {
      map['operation_key'] = Variable<String>(operationKey.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (lamport.present) {
      map['lamport'] = Variable<int>(lamport.value);
    }
    if (authorId.present) {
      map['author_id'] = Variable<String>(authorId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<int>(lastAttemptAt.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OpQueueRowsCompanion(')
          ..write('operationKey: $operationKey, ')
          ..write('documentId: $documentId, ')
          ..write('lamport: $lamport, ')
          ..write('authorId: $authorId, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SnapshotRowsTable extends SnapshotRows
    with TableInfo<$SnapshotRowsTable, SnapshotEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SnapshotRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sinceMeta = const VerificationMeta('since');
  @override
  late final GeneratedColumn<int> since = GeneratedColumn<int>(
    'since',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxLamportMeta = const VerificationMeta(
    'maxLamport',
  );
  @override
  late final GeneratedColumn<int> maxLamport = GeneratedColumn<int>(
    'max_lamport',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    documentId,
    since,
    maxLamport,
    payload,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snapshot_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SnapshotEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('since')) {
      context.handle(
        _sinceMeta,
        since.isAcceptableOrUnknown(data['since']!, _sinceMeta),
      );
    } else if (isInserting) {
      context.missing(_sinceMeta);
    }
    if (data.containsKey('max_lamport')) {
      context.handle(
        _maxLamportMeta,
        maxLamport.isAcceptableOrUnknown(data['max_lamport']!, _maxLamportMeta),
      );
    } else if (isInserting) {
      context.missing(_maxLamportMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId};
  @override
  SnapshotEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SnapshotEntry(
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      )!,
      since: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}since'],
      )!,
      maxLamport: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_lamport'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SnapshotRowsTable createAlias(String alias) {
    return $SnapshotRowsTable(attachedDatabase, alias);
  }
}

class SnapshotEntry extends DataClass implements Insertable<SnapshotEntry> {
  /// The document the snapshot belongs to.
  final String documentId;

  /// The cursor of the last operation pulled from the API.
  final int since;

  /// The highest Lamport timestamp observed for the document.
  final int maxLamport;

  /// The encoded snapshot, in JSON.
  final String payload;

  /// The moment of the last write, in milliseconds.
  final int updatedAt;
  const SnapshotEntry({
    required this.documentId,
    required this.since,
    required this.maxLamport,
    required this.payload,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<String>(documentId);
    map['since'] = Variable<int>(since);
    map['max_lamport'] = Variable<int>(maxLamport);
    map['payload'] = Variable<String>(payload);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SnapshotRowsCompanion toCompanion(bool nullToAbsent) {
    return SnapshotRowsCompanion(
      documentId: Value(documentId),
      since: Value(since),
      maxLamport: Value(maxLamport),
      payload: Value(payload),
      updatedAt: Value(updatedAt),
    );
  }

  factory SnapshotEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SnapshotEntry(
      documentId: serializer.fromJson<String>(json['documentId']),
      since: serializer.fromJson<int>(json['since']),
      maxLamport: serializer.fromJson<int>(json['maxLamport']),
      payload: serializer.fromJson<String>(json['payload']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<String>(documentId),
      'since': serializer.toJson<int>(since),
      'maxLamport': serializer.toJson<int>(maxLamport),
      'payload': serializer.toJson<String>(payload),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SnapshotEntry copyWith({
    String? documentId,
    int? since,
    int? maxLamport,
    String? payload,
    int? updatedAt,
  }) => SnapshotEntry(
    documentId: documentId ?? this.documentId,
    since: since ?? this.since,
    maxLamport: maxLamport ?? this.maxLamport,
    payload: payload ?? this.payload,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SnapshotEntry copyWithCompanion(SnapshotRowsCompanion data) {
    return SnapshotEntry(
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      since: data.since.present ? data.since.value : this.since,
      maxLamport: data.maxLamport.present
          ? data.maxLamport.value
          : this.maxLamport,
      payload: data.payload.present ? data.payload.value : this.payload,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotEntry(')
          ..write('documentId: $documentId, ')
          ..write('since: $since, ')
          ..write('maxLamport: $maxLamport, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(documentId, since, maxLamport, payload, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnapshotEntry &&
          other.documentId == this.documentId &&
          other.since == this.since &&
          other.maxLamport == this.maxLamport &&
          other.payload == this.payload &&
          other.updatedAt == this.updatedAt);
}

class SnapshotRowsCompanion extends UpdateCompanion<SnapshotEntry> {
  final Value<String> documentId;
  final Value<int> since;
  final Value<int> maxLamport;
  final Value<String> payload;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SnapshotRowsCompanion({
    this.documentId = const Value.absent(),
    this.since = const Value.absent(),
    this.maxLamport = const Value.absent(),
    this.payload = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnapshotRowsCompanion.insert({
    required String documentId,
    required int since,
    required int maxLamport,
    required String payload,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : documentId = Value(documentId),
       since = Value(since),
       maxLamport = Value(maxLamport),
       payload = Value(payload),
       updatedAt = Value(updatedAt);
  static Insertable<SnapshotEntry> custom({
    Expression<String>? documentId,
    Expression<int>? since,
    Expression<int>? maxLamport,
    Expression<String>? payload,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (since != null) 'since': since,
      if (maxLamport != null) 'max_lamport': maxLamport,
      if (payload != null) 'payload': payload,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnapshotRowsCompanion copyWith({
    Value<String>? documentId,
    Value<int>? since,
    Value<int>? maxLamport,
    Value<String>? payload,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SnapshotRowsCompanion(
      documentId: documentId ?? this.documentId,
      since: since ?? this.since,
      maxLamport: maxLamport ?? this.maxLamport,
      payload: payload ?? this.payload,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (since.present) {
      map['since'] = Variable<int>(since.value);
    }
    if (maxLamport.present) {
      map['max_lamport'] = Variable<int>(maxLamport.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotRowsCompanion(')
          ..write('documentId: $documentId, ')
          ..write('since: $since, ')
          ..write('maxLamport: $maxLamport, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SyncDatabase extends GeneratedDatabase {
  _$SyncDatabase(QueryExecutor e) : super(e);
  $SyncDatabaseManager get managers => $SyncDatabaseManager(this);
  late final $OpQueueRowsTable opQueueRows = $OpQueueRowsTable(this);
  late final $SnapshotRowsTable snapshotRows = $SnapshotRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    opQueueRows,
    snapshotRows,
  ];
}

typedef $$OpQueueRowsTableCreateCompanionBuilder =
    OpQueueRowsCompanion Function({
      required String operationKey,
      required String documentId,
      required int lamport,
      required String authorId,
      required String status,
      Value<int> attempts,
      required String payload,
      required int createdAt,
      Value<int?> lastAttemptAt,
      Value<int?> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$OpQueueRowsTableUpdateCompanionBuilder =
    OpQueueRowsCompanion Function({
      Value<String> operationKey,
      Value<String> documentId,
      Value<int> lamport,
      Value<String> authorId,
      Value<String> status,
      Value<int> attempts,
      Value<String> payload,
      Value<int> createdAt,
      Value<int?> lastAttemptAt,
      Value<int?> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$OpQueueRowsTableFilterComposer
    extends Composer<_$SyncDatabase, $OpQueueRowsTable> {
  $$OpQueueRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationKey => $composableBuilder(
    column: $table.operationKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorId => $composableBuilder(
    column: $table.authorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OpQueueRowsTableOrderingComposer
    extends Composer<_$SyncDatabase, $OpQueueRowsTable> {
  $$OpQueueRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationKey => $composableBuilder(
    column: $table.operationKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lamport => $composableBuilder(
    column: $table.lamport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorId => $composableBuilder(
    column: $table.authorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OpQueueRowsTableAnnotationComposer
    extends Composer<_$SyncDatabase, $OpQueueRowsTable> {
  $$OpQueueRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationKey => $composableBuilder(
    column: $table.operationKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lamport =>
      $composableBuilder(column: $table.lamport, builder: (column) => column);

  GeneratedColumn<String> get authorId =>
      $composableBuilder(column: $table.authorId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OpQueueRowsTableTableManager
    extends
        RootTableManager<
          _$SyncDatabase,
          $OpQueueRowsTable,
          OpQueueEntry,
          $$OpQueueRowsTableFilterComposer,
          $$OpQueueRowsTableOrderingComposer,
          $$OpQueueRowsTableAnnotationComposer,
          $$OpQueueRowsTableCreateCompanionBuilder,
          $$OpQueueRowsTableUpdateCompanionBuilder,
          (
            OpQueueEntry,
            BaseReferences<_$SyncDatabase, $OpQueueRowsTable, OpQueueEntry>,
          ),
          OpQueueEntry,
          PrefetchHooks Function()
        > {
  $$OpQueueRowsTableTableManager(_$SyncDatabase db, $OpQueueRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OpQueueRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OpQueueRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OpQueueRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> operationKey = const Value.absent(),
                Value<String> documentId = const Value.absent(),
                Value<int> lamport = const Value.absent(),
                Value<String> authorId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> lastAttemptAt = const Value.absent(),
                Value<int?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OpQueueRowsCompanion(
                operationKey: operationKey,
                documentId: documentId,
                lamport: lamport,
                authorId: authorId,
                status: status,
                attempts: attempts,
                payload: payload,
                createdAt: createdAt,
                lastAttemptAt: lastAttemptAt,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationKey,
                required String documentId,
                required int lamport,
                required String authorId,
                required String status,
                Value<int> attempts = const Value.absent(),
                required String payload,
                required int createdAt,
                Value<int?> lastAttemptAt = const Value.absent(),
                Value<int?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OpQueueRowsCompanion.insert(
                operationKey: operationKey,
                documentId: documentId,
                lamport: lamport,
                authorId: authorId,
                status: status,
                attempts: attempts,
                payload: payload,
                createdAt: createdAt,
                lastAttemptAt: lastAttemptAt,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OpQueueRowsTable, OpQueueEntry>(table),
                  BaseReferences<
                    _$SyncDatabase,
                    $OpQueueRowsTable,
                    OpQueueEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OpQueueRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$SyncDatabase,
      $OpQueueRowsTable,
      OpQueueEntry,
      $$OpQueueRowsTableFilterComposer,
      $$OpQueueRowsTableOrderingComposer,
      $$OpQueueRowsTableAnnotationComposer,
      $$OpQueueRowsTableCreateCompanionBuilder,
      $$OpQueueRowsTableUpdateCompanionBuilder,
      (
        OpQueueEntry,
        BaseReferences<_$SyncDatabase, $OpQueueRowsTable, OpQueueEntry>,
      ),
      OpQueueEntry,
      PrefetchHooks Function()
    >;
typedef $$SnapshotRowsTableCreateCompanionBuilder =
    SnapshotRowsCompanion Function({
      required String documentId,
      required int since,
      required int maxLamport,
      required String payload,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$SnapshotRowsTableUpdateCompanionBuilder =
    SnapshotRowsCompanion Function({
      Value<String> documentId,
      Value<int> since,
      Value<int> maxLamport,
      Value<String> payload,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$SnapshotRowsTableFilterComposer
    extends Composer<_$SyncDatabase, $SnapshotRowsTable> {
  $$SnapshotRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get since => $composableBuilder(
    column: $table.since,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxLamport => $composableBuilder(
    column: $table.maxLamport,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SnapshotRowsTableOrderingComposer
    extends Composer<_$SyncDatabase, $SnapshotRowsTable> {
  $$SnapshotRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get since => $composableBuilder(
    column: $table.since,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxLamport => $composableBuilder(
    column: $table.maxLamport,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SnapshotRowsTableAnnotationComposer
    extends Composer<_$SyncDatabase, $SnapshotRowsTable> {
  $$SnapshotRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get since =>
      $composableBuilder(column: $table.since, builder: (column) => column);

  GeneratedColumn<int> get maxLamport => $composableBuilder(
    column: $table.maxLamport,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SnapshotRowsTableTableManager
    extends
        RootTableManager<
          _$SyncDatabase,
          $SnapshotRowsTable,
          SnapshotEntry,
          $$SnapshotRowsTableFilterComposer,
          $$SnapshotRowsTableOrderingComposer,
          $$SnapshotRowsTableAnnotationComposer,
          $$SnapshotRowsTableCreateCompanionBuilder,
          $$SnapshotRowsTableUpdateCompanionBuilder,
          (
            SnapshotEntry,
            BaseReferences<_$SyncDatabase, $SnapshotRowsTable, SnapshotEntry>,
          ),
          SnapshotEntry,
          PrefetchHooks Function()
        > {
  $$SnapshotRowsTableTableManager(_$SyncDatabase db, $SnapshotRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SnapshotRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SnapshotRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SnapshotRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> documentId = const Value.absent(),
                Value<int> since = const Value.absent(),
                Value<int> maxLamport = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnapshotRowsCompanion(
                documentId: documentId,
                since: since,
                maxLamport: maxLamport,
                payload: payload,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String documentId,
                required int since,
                required int maxLamport,
                required String payload,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SnapshotRowsCompanion.insert(
                documentId: documentId,
                since: since,
                maxLamport: maxLamport,
                payload: payload,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SnapshotRowsTable, SnapshotEntry>(table),
                  BaseReferences<
                    _$SyncDatabase,
                    $SnapshotRowsTable,
                    SnapshotEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SnapshotRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$SyncDatabase,
      $SnapshotRowsTable,
      SnapshotEntry,
      $$SnapshotRowsTableFilterComposer,
      $$SnapshotRowsTableOrderingComposer,
      $$SnapshotRowsTableAnnotationComposer,
      $$SnapshotRowsTableCreateCompanionBuilder,
      $$SnapshotRowsTableUpdateCompanionBuilder,
      (
        SnapshotEntry,
        BaseReferences<_$SyncDatabase, $SnapshotRowsTable, SnapshotEntry>,
      ),
      SnapshotEntry,
      PrefetchHooks Function()
    >;

class $SyncDatabaseManager {
  final _$SyncDatabase _db;
  $SyncDatabaseManager(this._db);
  $$OpQueueRowsTableTableManager get opQueueRows =>
      $$OpQueueRowsTableTableManager(_db, _db.opQueueRows);
  $$SnapshotRowsTableTableManager get snapshotRows =>
      $$SnapshotRowsTableTableManager(_db, _db.snapshotRows);
}
