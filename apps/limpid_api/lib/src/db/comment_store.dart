import 'package:limpid_core/limpid_core.dart';
import 'package:postgres/postgres.dart';
import 'package:sqlite3/sqlite3.dart';

import '../errors/app_exception.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// The maximum length of an identifier of a discussion or of a message.
const int maxCommentIdLength = 64;

/// The maximum length of the body of a message.
const int maxCommentBodyLength = 8000;

/// The maximum length of the excerpt carried by a discussion.
const int maxCommentExcerptLength = 1000;

/// The maximum number of messages a discussion may hold.
const int maxCommentsPerThread = 500;

/// A collaborator of a project, with the role it holds inside it.
typedef CommentMember = ({String userId, String displayName, ProjectRole role});

/// A discussion, with the metadata the server keeps about it.
typedef StoredThread = ({
  CommentThread thread,
  String excerpt,
  DateTime createdAt,
  DateTime updatedAt,
});

/// The persistence port of the discussions.
///
/// The API never talks to a database directly: it goes through this port,
/// which the composition root replaces with the implementation of the engine
/// in use (SQLite in development, Postgres in production).
abstract interface class CommentStore {
  /// The discussions of a project, the oldest first.
  Future<List<StoredThread>> listThreads({required String projectId});

  /// Writes a discussion and its messages, and returns the stored discussion.
  Future<StoredThread> saveThread({
    required String projectId,
    required CommentThread thread,
    String excerpt,
  });

  /// The collaborators of a project, its owner included.
  Future<List<CommentMember>> listMembers({required String projectId});
}

/// The SQL port of the discussions.
///
/// The dialect is confined to the adapters: SQLite and Postgres differ on
/// the placeholders, on the timestamps and on the booleans (D-29). The SQL
/// itself is written once, with the `?` placeholders of SQLite.
abstract interface class CommentDatabase {
  /// Rewrites the `?` placeholders of [sql] for the engine.
  String rewrite(String sql);

  /// Runs the query [sql] and returns its rows.
  Future<List<Map<String, Object?>>> query(String sql, List<Object?> args);

  /// Runs [statements] in a single transaction.
  Future<void> transaction(List<(String, List<Object?>)> statements);

  /// Encodes a timestamp for the engine.
  Object? encodeTimestamp(DateTime? value);

  /// Decodes a timestamp read from the engine.
  DateTime? decodeTimestamp(Object? value);

  /// Encodes a boolean for the engine.
  Object encodeBoolean(bool value);

  /// Decodes a boolean read from the engine.
  bool decodeBoolean(Object? value);
}

/// The SQLite adapter of the discussions.
///
/// The timestamps are the microseconds since the Unix epoch and the booleans
/// are `0` or `1`: the convention of the SQLite dialect (see `SqliteValues`).
final class SqliteCommentDatabase implements CommentDatabase {
  /// Creates an adapter on top of [database].
  const SqliteCommentDatabase(this._database);

  /// The database of the API.
  final SqliteDatabase _database;

  @override
  String rewrite(String sql) => sql;

  @override
  Future<List<Map<String, Object?>>> query(String sql, List<Object?> args) =>
      _database.run(() {
        final ResultSet result = _database.connection.select(sql, args);
        return result
            .map((Row row) => Map<String, Object?>.from(row))
            .toList(growable: false);
      });

  @override
  Future<void> transaction(List<(String, List<Object?>)> statements) =>
      _database.transaction(() {
        for (final (String sql, List<Object?> args) in statements) {
          _database.connection.execute(sql, args);
        }
      });

  @override
  Object? encodeTimestamp(DateTime? value) =>
      value == null ? null : SqliteValues.encodeTimestamp(value);

  @override
  DateTime? decodeTimestamp(Object? value) =>
      value == null ? null : SqliteValues.decodeTimestamp(value);

  @override
  Object encodeBoolean(bool value) => SqliteValues.encodeBoolean(value);

  @override
  bool decodeBoolean(Object? value) => SqliteValues.decodeBoolean(value);
}

/// The Postgres adapter of the discussions.
///
/// The timestamps are sent as `TIMESTAMPTZ` and the booleans as `BOOLEAN`;
/// the placeholders of the SQL are rewritten into the indexed form of the
/// protocol (`$1`, `$2`…).
final class PostgresCommentDatabase implements CommentDatabase {
  /// Creates an adapter on top of [pool].
  const PostgresCommentDatabase(this._pool);

  /// The pool of the API.
  final Pool<Object?> _pool;

  @override
  String rewrite(String sql) {
    var index = 0;
    return sql.replaceAllMapped(RegExp(r'\?'), (Match _) => '\$${++index}');
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> args,
  ) async {
    final Result result = await _pool.execute(rewrite(sql), parameters: args);
    return result
        .map((ResultRow row) => Map<String, Object?>.from(row.toColumnMap()))
        .toList(growable: false);
  }

  @override
  Future<void> transaction(List<(String, List<Object?>)> statements) async {
    await _pool.runTx((TxSession session) async {
      for (final (String sql, List<Object?> args) in statements) {
        await session.execute(rewrite(sql), parameters: args);
      }
    });
  }

  @override
  Object? encodeTimestamp(DateTime? value) => value?.toUtc();

  @override
  DateTime? decodeTimestamp(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
  }

  @override
  Object encodeBoolean(bool value) => value;

  @override
  bool decodeBoolean(Object? value) => value == true;
}

/// The store of the discussions, backed by SQL.
///
/// Every statement is parameterized: no value ever reaches the engine
/// through string concatenation. The write of a discussion and of its
/// messages happens in a single transaction.
final class SqlCommentStore implements CommentStore {
  /// Creates a store on top of [database].
  const SqlCommentStore(this._database);

  /// The SQL port of the store.
  final CommentDatabase _database;

  static const String _threadColumns =
      'id, mark_id, excerpt, is_resolved, resolved_at, created_at, updated_at';

  static const String _commentColumns =
      'id, thread_id, author_id, body, created_at, edited_at';

  @override
  Future<List<StoredThread>> listThreads({required String projectId}) async {
    final List<Map<String, Object?>> threads = await _database.query(
      'SELECT $_threadColumns FROM comment_threads WHERE project_id = ? '
      'ORDER BY created_at ASC, id ASC',
      <Object?>[projectId],
    );
    final List<Map<String, Object?>> comments = await _database.query(
      'SELECT $_commentColumns FROM comments WHERE thread_id IN '
      '(SELECT id FROM comment_threads WHERE project_id = ?) '
      'ORDER BY created_at ASC, id ASC',
      <Object?>[projectId],
    );
    return List<StoredThread>.unmodifiable(_threadsOf(threads, comments));
  }

  @override
  Future<StoredThread> saveThread({
    required String projectId,
    required CommentThread thread,
    String excerpt = '',
  }) async {
    await _requireSameProject(projectId, thread.id.value);

    final DateTime now = DateTime.now().toUtc();
    await _database.transaction(<(String, List<Object?>)>[
      (
        'INSERT INTO comment_threads (id, project_id, mark_id, excerpt, '
            'is_resolved, created_at, updated_at, resolved_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
            'ON CONFLICT(id) DO UPDATE SET mark_id = excluded.mark_id, '
            'excerpt = excluded.excerpt, is_resolved = excluded.is_resolved, '
            'updated_at = excluded.updated_at, resolved_at = excluded.resolved_at '
            'WHERE comment_threads.project_id = excluded.project_id',
        <Object?>[
          thread.id.value,
          projectId,
          thread.markId.value,
          excerpt,
          _database.encodeBoolean(thread.isResolved),
          _database.encodeTimestamp(now),
          _database.encodeTimestamp(now),
          _database.encodeTimestamp(thread.resolvedAt),
        ],
      ),
      for (final Comment comment in thread.comments) _commentStatement(comment),
      _deletionOf(thread),
    ]);

    final StoredThread? stored = await _storedThread(thread.id.value);
    if (stored == null) {
      throw StateError('The thread ${thread.id.value} could not be read back.');
    }
    return stored;
  }

  @override
  Future<List<CommentMember>> listMembers({required String projectId}) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'SELECT p.owner_id AS user_id, \'owner\' AS role FROM projects p '
      'WHERE p.id = ? '
      'UNION ALL '
      'SELECT m.user_id AS user_id, m.role AS role FROM project_members m '
      'WHERE m.project_id = ? '
      'ORDER BY user_id ASC',
      <Object?>[projectId, projectId],
    );
    return List<CommentMember>.unmodifiable(rows.map(_memberOf));
  }

  /// The stored discussion of [threadId], `null` when it does not exist.
  Future<StoredThread?> _storedThread(String threadId) async {
    final List<Map<String, Object?>> threads = await _database.query(
      'SELECT $_threadColumns FROM comment_threads WHERE id = ?',
      <Object?>[threadId],
    );
    if (threads.isEmpty) return null;
    final List<Map<String, Object?>> comments = await _database.query(
      'SELECT $_commentColumns FROM comments WHERE thread_id = ? '
      'ORDER BY created_at ASC, id ASC',
      <Object?>[threadId],
    );
    return _threadsOf(threads, comments).first;
  }

  /// Refuses to move a discussion to another project.
  Future<void> _requireSameProject(String projectId, String threadId) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'SELECT project_id FROM comment_threads WHERE id = ?',
      <Object?>[threadId],
    );
    if (rows.isEmpty) return;
    if (_text(rows.first, 'project_id') == projectId) return;
    throw const ConflictException(
      message: 'Cette discussion appartient à un autre projet.',
    );
  }

  /// The statement writing a message of a discussion.
  (String, List<Object?>) _commentStatement(Comment comment) {
    return (
      'INSERT INTO comments (id, thread_id, author_id, body, created_at, '
          'edited_at) VALUES (?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(id) DO UPDATE SET thread_id = excluded.thread_id, '
          'author_id = excluded.author_id, body = excluded.body, '
          'edited_at = excluded.edited_at',
      <Object?>[
        comment.id.value,
        comment.threadId.value,
        comment.author.value,
        comment.body,
        _database.encodeTimestamp(comment.createdAt),
        _database.encodeTimestamp(comment.editedAt),
      ],
    );
  }

  /// The statement removing the messages that left the discussion.
  (String, List<Object?>) _deletionOf(CommentThread thread) {
    final List<String> kept = thread.comments
        .map((Comment comment) => comment.id.value)
        .toList(growable: false);
    if (kept.isEmpty) {
      return (
        'DELETE FROM comments WHERE thread_id = ?',
        <Object?>[thread.id.value],
      );
    }
    final String placeholders = List<String>.filled(
      kept.length,
      '?',
    ).join(', ');
    return (
      'DELETE FROM comments WHERE thread_id = ? AND id NOT IN ($placeholders)',
      <Object?>[thread.id.value, ...kept],
    );
  }

  /// Rebuilds the discussions from their rows.
  List<StoredThread> _threadsOf(
    List<Map<String, Object?>> threads,
    List<Map<String, Object?>> comments,
  ) {
    final Map<String, List<Comment>> messages = <String, List<Comment>>{};
    for (final Map<String, Object?> row in comments) {
      messages
          .putIfAbsent(_text(row, 'thread_id'), () => <Comment>[])
          .add(
            Comment(
              id: CommentId(_text(row, 'id')),
              threadId: CommentId(_text(row, 'thread_id')),
              author: AuthorId(_text(row, 'author_id')),
              body: _text(row, 'body'),
              createdAt: _database.decodeTimestamp(row['created_at']) ?? _epoch,
              editedAt: _database.decodeTimestamp(row['edited_at']),
            ),
          );
    }
    return threads
        .map(
          (Map<String, Object?> row) => (
            thread: CommentThread(
              id: CommentId(_text(row, 'id')),
              markId: MarkId(_text(row, 'mark_id')),
              comments: messages[_text(row, 'id')] ?? const <Comment>[],
              isResolved: _database.decodeBoolean(row['is_resolved']),
              resolvedAt: _database.decodeTimestamp(row['resolved_at']),
            ),
            excerpt: _text(row, 'excerpt'),
            createdAt: _database.decodeTimestamp(row['created_at']) ?? _epoch,
            updatedAt: _database.decodeTimestamp(row['updated_at']) ?? _epoch,
          ),
        )
        .toList(growable: false);
  }

  /// Reads a collaborator from its row.
  CommentMember _memberOf(Map<String, Object?> row) {
    final String userId = _text(row, 'user_id');
    return (userId: userId, displayName: userId, role: _roleOf(row));
  }

  /// Reads a column of text, an empty string when it is missing.
  static String _text(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is String ? value : '';
  }

  /// Reads the role of a row, the most restrictive one when it is unknown.
  static ProjectRole _roleOf(Map<String, Object?> row) {
    final String name = _text(row, 'role');
    for (final ProjectRole role in ProjectRole.values) {
      if (role.name == name) return role;
    }
    return ProjectRole.reader;
  }

  /// The moment the epoch starts, used when a timestamp is missing.
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );
}

/// A store of the discussions kept in the memory of the process.
///
/// The tests of the API use it: they exercise the routes without a
/// database. It holds the discussions of the projects it is given, and no
/// membership — the collaborators live in the table of the projects.
final class InMemoryCommentStore implements CommentStore {
  /// The discussions, by project.
  final Map<String, List<StoredThread>> _threads =
      <String, List<StoredThread>>{};

  /// The collaborators of the projects, by project.
  final Map<String, List<CommentMember>> _members =
      <String, List<CommentMember>>{};

  /// Adds a collaborator to a project.
  void addMember(String projectId, CommentMember member) {
    _members.putIfAbsent(projectId, () => <CommentMember>[]).add(member);
  }

  @override
  Future<List<StoredThread>> listThreads({required String projectId}) async {
    return List<StoredThread>.unmodifiable(
      _threads[projectId] ?? const <StoredThread>[],
    );
  }

  @override
  Future<StoredThread> saveThread({
    required String projectId,
    required CommentThread thread,
    String excerpt = '',
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final StoredThread stored = (
      thread: thread,
      excerpt: excerpt,
      createdAt: now,
      updatedAt: now,
    );
    final List<StoredThread> threads = _threads.putIfAbsent(
      projectId,
      () => <StoredThread>[],
    );
    final int index = threads.indexWhere(
      (StoredThread candidate) => candidate.thread.id == thread.id,
    );
    if (index >= 0) {
      threads[index] = stored;
    } else {
      threads.add(stored);
    }
    return stored;
  }

  @override
  Future<List<CommentMember>> listMembers({required String projectId}) async {
    return List<CommentMember>.unmodifiable(
      _members[projectId] ?? const <CommentMember>[],
    );
  }
}
