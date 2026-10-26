import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// A SQLite database owned by the API.
///
/// The `sqlite3` package is **synchronous**: every call blocks the isolate
/// for the whole duration of the statement. The accesses are therefore
/// serialized by [run], a FIFO queue that guarantees two statements never
/// overlap and that a transaction is never interleaved with another one.
/// The queue is the guard-fou of the API: it replaces the `synchronized`
/// package, which is not a dependency of this application.
///
/// The queue gives two guarantees:
///
/// - the statements are executed one after the other, in the order they were
///   submitted, which keeps the writes serialisable;
/// - a transaction opened by [transaction] is never interleaved with another
///   transaction, so `BEGIN` / `COMMIT` pairs always match.
///
/// It does **not** make the engine asynchronous: the isolate is blocked while
/// a statement runs. The development database is small and local, so the
/// latency stays below the millisecond.
final class SqliteDatabase {
  SqliteDatabase._(this._connection);

  /// Opens the database file at [path].
  ///
  /// The parent directory is created when it does not exist yet, so a fresh
  /// workstation boots the API without any manual step. The foreign keys are
  /// enabled to match the behaviour of Postgres, and the write-ahead log
  /// keeps the readers from blocking the writers.
  static Future<SqliteDatabase> open(String path) async {
    final Directory parent = Directory(path).parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    final Database connection = sqlite3.open(path);
    connection.execute('PRAGMA foreign_keys = ON');
    connection.execute('PRAGMA busy_timeout = 5000');
    connection.execute('PRAGMA journal_mode = WAL');
    return SqliteDatabase._(connection);
  }

  /// Opens a private in-memory database, used by the test suite.
  ///
  /// The database lives in the `:memory:` database of SQLite: it is private
  /// to the connection and disappears when the connection is closed.
  static Future<SqliteDatabase> openInMemory() async {
    final Database connection = sqlite3.openInMemory();
    connection.execute('PRAGMA foreign_keys = ON');
    connection.execute('PRAGMA busy_timeout = 5000');
    return SqliteDatabase._(connection);
  }

  final Database _connection;

  /// The tail of the queue: the future of the last submitted action.
  Future<void> _tail = Future<void>.value();

  /// Whether the connection is already closed.
  bool _isClosed = false;

  /// The raw connection, for the callers driving the SQL API directly.
  Database get connection => _connection;

  /// Runs [action] once every previously submitted action is done.
  ///
  /// The action must not call [run] again: the queue would wait for itself.
  Future<T> run<T>(T Function() action) {
    final Completer<T> completer = Completer<T>();
    _tail = _tail.then((_) {
      try {
        completer.complete(action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Runs [action] inside a transaction.
  ///
  /// The transaction is rolled back when [action] throws; the error is then
  /// forwarded to the caller untouched.
  Future<T> transaction<T>(T Function() action) {
    return run(() {
      _connection.execute('BEGIN');
      try {
        final T result = action();
        _connection.execute('COMMIT');
        return result;
      } on Object {
        _connection.execute('ROLLBACK');
        rethrow;
      }
    });
  }

  /// Closes the connection once the queued actions are done.
  ///
  /// The method is idempotent: closing an already closed database is a
  /// no-op, so the shutdown path may run twice without failing.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _tail;
    _connection.close();
  }
}
