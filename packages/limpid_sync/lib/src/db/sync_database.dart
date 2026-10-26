import 'package:drift/drift.dart';

part 'sync_database.g.dart';

/// The rows of the local operation queue.
///
/// The table is the durable memory of the offline-first promise: an
/// operation is written here before the first attempt to send it.
@DataClassName('OpQueueEntry')
class OpQueueRows extends Table {
  /// The identity of the operation, `(doc_id, lamport, author_id)`.
  TextColumn get operationKey => text()();

  /// The document the operation belongs to.
  TextColumn get documentId => text()();

  /// The Lamport timestamp of the operation.
  IntColumn get lamport => integer()();

  /// The author of the operation.
  TextColumn get authorId => text()();

  /// The state of the entry: `pending`, `sent` or `failed`.
  TextColumn get status => text()();

  /// The number of attempts already made.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// The encoded operation, in the wire format of the API.
  TextColumn get payload => text()();

  /// The moment the operation entered the queue, in milliseconds.
  IntColumn get createdAt => integer()();

  /// The moment of the last attempt, in milliseconds.
  IntColumn get lastAttemptAt => integer().nullable()();

  /// The earliest moment of the next attempt, in milliseconds.
  IntColumn get nextAttemptAt => integer().nullable()();

  /// The reason of the last failure.
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {operationKey};
}

/// The rows of the local document snapshots.
///
/// A snapshot stores the compacted operation journal of a document and the
/// cursor of the API, so the client does not pull the whole history again at
/// startup.
@DataClassName('SnapshotEntry')
class SnapshotRows extends Table {
  /// The document the snapshot belongs to.
  TextColumn get documentId => text()();

  /// The cursor of the last operation pulled from the API.
  IntColumn get since => integer()();

  /// The highest Lamport timestamp observed for the document.
  IntColumn get maxLamport => integer()();

  /// The encoded snapshot, in JSON.
  TextColumn get payload => text()();

  /// The moment of the last write, in milliseconds.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {documentId};
}

/// The local database of the sync client.
///
/// The database is opened by the application: `limpid_sync` never opens a
/// file by itself, it only manipulates the executor it is given. A Flutter
/// application passes a `NativeDatabase` created on the
/// `sqlite3_flutter_libs` bundle, a pure Dart application passes
/// `NativeDatabase.memory()`.
@DriftDatabase(tables: <Type>[OpQueueRows, SnapshotRows])
class SyncDatabase extends _$SyncDatabase {
  /// Creates a database on top of [e], a Drift query executor.
  SyncDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
