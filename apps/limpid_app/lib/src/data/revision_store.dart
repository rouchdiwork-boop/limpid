import 'package:drift/drift.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The discussions of the projects, stored in the local database.
///
/// The store owns the SQL of the review: the repository of the data layer
/// only translates the rows into the entities of `limpid_core`.
///
/// Every statement is parameterised: the values never reach the SQL text.
final class RevisionStore {
  /// Creates a store on top of [database].
  RevisionStore(this._database);

  /// The Drift database holding the tables.
  final SyncDatabase _database;

  /// The discussions of a project, the oldest first.
  ///
  /// A project that holds no discussion answers with an empty list: the
  /// caller never has to know whether the project exists.
  Future<List<CommentThread>> listThreads(String projectId) async {
    final List<Map<String, Object?>> rows = await _select(
      'SELECT t.id AS thread_id, t.mark_id, t.is_resolved, t.resolved_at, '
      'c.id AS comment_id, c.author_id, c.body, '
      'c.created_at AS comment_created_at, c.edited_at AS comment_edited_at '
      'FROM comment_threads t '
      'LEFT JOIN comments c ON c.thread_id = t.id '
      'WHERE t.project_id = ? '
      'ORDER BY t.created_at ASC, t.id ASC, c.created_at ASC, c.id ASC',
      <Object?>[projectId],
    );
    return List<CommentThread>.unmodifiable(_threadsOf(rows));
  }

  /// Writes a discussion and its messages.
  ///
  /// The write is idempotent: the discussion is keyed by its identifier and
  /// its messages are keyed by theirs. The messages that left the discussion
  /// are removed, so the stored conversation is always the written one.
  Future<void> saveThread(String projectId, CommentThread thread) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await _execute(
        '''
INSERT INTO comment_threads (
  id, project_id, mark_id, excerpt, is_resolved,
  created_at, updated_at, resolved_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  mark_id = excluded.mark_id,
  is_resolved = excluded.is_resolved,
  updated_at = excluded.updated_at,
  resolved_at = excluded.resolved_at''',
        <Object?>[
          thread.id.value,
          projectId,
          thread.markId.value,
          '',
          _integerOf(thread.isResolved),
          now,
          now,
          thread.resolvedAt?.millisecondsSinceEpoch,
        ],
      );

      for (final Comment comment in thread.comments) {
        await _execute(
          '''
INSERT INTO comments (
  id, thread_id, author_id, body, created_at, edited_at
) VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  thread_id = excluded.thread_id,
  author_id = excluded.author_id,
  body = excluded.body,
  edited_at = excluded.edited_at''',
          <Object?>[
            comment.id.value,
            thread.id.value,
            comment.author.value,
            comment.body,
            comment.createdAt.millisecondsSinceEpoch,
            comment.editedAt?.millisecondsSinceEpoch,
          ],
        );
      }

      await _removeDroppedComments(thread.id.value, thread.comments);
    });
  }

  /// The owner of a project, `null` when the project is unknown.
  ///
  /// The local database knows the owner of a project and nothing else: the
  /// collaborators come from the server.
  Future<String?> findProjectOwner(String projectId) async {
    final Map<String, Object?>? row = await _selectOne(
      'SELECT owner_id FROM projects WHERE id = ?',
      <Object?>[projectId],
    );
    if (row == null) return null;
    final String owner = _text(row, 'owner_id');
    return owner.isEmpty ? null : owner;
  }

  /// Removes the messages that are no longer part of the discussion.
  Future<void> _removeDroppedComments(
    String threadId,
    List<Comment> comments,
  ) async {
    final List<String> kept = comments
        .map((Comment comment) => comment.id.value)
        .toList(growable: false);
    if (kept.isEmpty) {
      await _execute('DELETE FROM comments WHERE thread_id = ?', <Object?>[
        threadId,
      ]);
      return;
    }
    final String placeholders = List<String>.filled(
      kept.length,
      '?',
    ).join(', ');
    await _execute(
      'DELETE FROM comments WHERE thread_id = ? AND id NOT IN ($placeholders)',
      <Object?>[threadId, ...kept],
    );
  }

  /// Rebuilds the discussions from the rows of the join.
  List<CommentThread> _threadsOf(List<Map<String, Object?>> rows) {
    final Map<String, List<Comment>> messages = <String, List<Comment>>{};
    final Map<String, CommentThread> threads = <String, CommentThread>{};

    for (final Map<String, Object?> row in rows) {
      final String threadId = _text(row, 'thread_id');
      threads.putIfAbsent(
        threadId,
        () => CommentThread(
          id: CommentId(threadId),
          markId: MarkId(_text(row, 'mark_id')),
          comments: const <Comment>[],
          isResolved: _boolean(row, 'is_resolved'),
          resolvedAt: _date(row, 'resolved_at'),
        ),
      );
      final String commentId = _text(row, 'comment_id');
      if (commentId.isEmpty) continue;
      messages
          .putIfAbsent(threadId, () => <Comment>[])
          .add(
            Comment(
              id: CommentId(commentId),
              threadId: CommentId(threadId),
              author: AuthorId(_text(row, 'author_id')),
              body: _text(row, 'body'),
              createdAt: _date(row, 'comment_created_at') ?? _epoch,
              editedAt: _date(row, 'comment_edited_at'),
            ),
          );
    }

    return threads.values
        .map(
          (CommentThread thread) => thread.copyWith(
            comments: messages[thread.id.value] ?? const <Comment>[],
          ),
        )
        .toList(growable: false);
  }

  /// Reads the rows matching [sql].
  Future<List<Map<String, Object?>>> _select(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async {
    final List<QueryRow> rows = await _database
        .customSelect(sql, variables: _variables(args))
        .get();
    return rows.map((QueryRow row) => row.data).toList(growable: false);
  }

  /// Reads the first row matching [sql], `null` when there is none.
  Future<Map<String, Object?>?> _selectOne(
    String sql, [
    List<Object?> args = const <Object?>[],
  ]) async {
    final List<Map<String, Object?>> rows = await _select(sql, args);
    return rows.isEmpty ? null : rows.first;
  }

  /// Runs a statement that writes.
  Future<void> _execute(String sql, List<Object?> args) async {
    await _database.customStatement(sql, args);
  }

  /// Builds the variables of a parameterised statement.
  List<Variable<Object>> _variables(List<Object?> args) =>
      args.map(_variable).toList(growable: false);

  /// Builds the variable holding [value].
  Variable<Object> _variable(Object? value) => switch (value) {
    final String text => Variable<String>(text),
    final int number => Variable<int>(number),
    final bool flag => Variable<bool>(flag),
    final double number => Variable<double>(number),
    null => const Variable<String>(null),
    _ => throw ArgumentError.value(
      value,
      'value',
      'Only text, numbers, booleans and null can be bound to a statement.',
    ),
  };

  /// The moment the epoch starts, used when a timestamp is missing.
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Reads a column of text, an empty string when it is missing.
  static String _text(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is String ? value : '';
  }

  /// Reads a column of integers, `0` when it is missing.
  static int _integer(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is int ? value : 0;
  }

  /// Reads a column of booleans, `false` when it is missing.
  static bool _boolean(Map<String, Object?> row, String column) =>
      _integer(row, column) != 0;

  /// Encodes a boolean as the integer SQLite stores.
  static int _integerOf(bool value) => value ? 1 : 0;

  /// Reads a column of timestamps.
  static DateTime? _date(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    if (value is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}
