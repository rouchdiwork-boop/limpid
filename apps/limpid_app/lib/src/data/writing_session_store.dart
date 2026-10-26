import 'package:drift/drift.dart';
import 'package:limpid_app/src/data/local_account_scope.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The writing sessions of the author, stored on the device.
///
/// The store is the only place that knows the table `writing_sessions`.
/// Everything it writes stays on the device: the sessions never reach the
/// server, and the criterion asks for statistics that work offline.
///
/// ## The day of a session
///
/// The day is a **local** day, written as `AAAA-MM-JJ`. The author writes on
/// their own days: the key of a day never depends on the time zone of the
/// server.
///
/// ## The two rows of a day
///
/// A day holds one row per book and one row that carries the **total** of
/// the author — the row whose `project_id` is empty. The total is what the
/// series of the writing days and the history of the writing read: it is
/// the sum of the books, and it never drifts from them because the two
/// rows are written in the same transaction.
///
/// ## The scope of the account
///
/// The sessions belong to the account of the session: the local database is
/// shared by every account of the device, and the days of writing of an
/// author never reach the dashboard of another.
final class WritingSessionStore {
  /// Creates a store on top of [database].
  WritingSessionStore(this._database, this._account);

  /// The Drift database holding the tables.
  final SyncDatabase _database;

  /// The account that owns the local data of the device.
  final LocalAccountScope _account;

  /// The identifier of the account that owns the local data right now.
  String get accountId => _account.accountId;

  /// The value of `project_id` that carries the total of the author.
  static const String totalProject = '';

  /// Records the words the author wrote in [projectId] on the day of [day].
  ///
  /// The session of the day grows by [words] and by [minutes]: the words are
  /// counted by difference, and a stroke that deletes words never counts as
  /// writing. A session without words is not written at all: a day on which
  /// the author wrote nothing is not a day of writing.
  ///
  /// The row of the book and the row of the total are written together: the
  /// total of a day is always the sum of its books.
  Future<void> recordWriting({
    required DateTime day,
    required String projectId,
    required int words,
    required int minutes,
    String? accountId,
  }) async {
    if (words <= 0) return;
    final String account = accountId ?? _account.accountId;
    final String key = dayKeyOf(day);
    final List<String> books = <String>[
      if (projectId.isNotEmpty) projectId,
      totalProject,
    ];

    await _database.transaction(() async {
      for (final String book in books) {
        await _execute(
          '''
INSERT INTO writing_sessions (account_id, day, project_id, words, minutes)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(account_id, day, project_id) DO UPDATE SET
  words = words + excluded.words,
  minutes = minutes + excluded.minutes''',
          <Object?>[account, key, book, words, minutes],
        );
      }
    });
  }

  /// The days on which the author wrote.
  ///
  /// The days come from the rows of the total: a day the author did not
  /// write on is never a day of writing, whatever the scenes were touched.
  ///
  /// The days are the local midnights, the oldest first.
  Future<List<DateTime>> listWritingDays({String? accountId}) async {
    final List<Map<String, Object?>> rows = await _select(
      'SELECT DISTINCT day FROM writing_sessions '
      'WHERE account_id = ? AND project_id = ? AND words > 0 '
      'ORDER BY day ASC',
      <Object?>[accountId ?? _account.accountId, totalProject],
    );
    return List<DateTime>.unmodifiable(
      rows
          .map((Map<String, Object?> row) => dayOfKey(_text(row, 'day')))
          .whereType<DateTime>(),
    );
  }

  /// The sessions written between [from] and [to], both included.
  ///
  /// The sessions are the rows of the total, ordered from the most recent
  /// day to the oldest one.
  Future<List<WritingSession>> listWritingSessions({
    required DateTime from,
    required DateTime to,
    String? accountId,
  }) async {
    final List<Map<String, Object?>> rows = await _select(
      'SELECT day, words, minutes FROM writing_sessions '
      'WHERE account_id = ? AND project_id = ? AND day >= ? AND day <= ? '
      'ORDER BY day DESC',
      <Object?>[
        accountId ?? _account.accountId,
        totalProject,
        dayKeyOf(from),
        dayKeyOf(to),
      ],
    );
    return List<WritingSession>.unmodifiable(
      rows.map(
        (Map<String, Object?> row) => WritingSession(
          day:
              dayOfKey(_text(row, 'day')) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          words: _integer(row, 'words'),
          minutes: _integer(row, 'minutes'),
        ),
      ),
    );
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
    _ => Variable<Object>(value),
  };

  /// The text of the column [column] of [row].
  static String _text(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is String ? value : '';
  }

  /// The integer of the column [column] of [row].
  static int _integer(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is int ? value : 0;
  }
}

/// The key of the local day of [moment], written as `AAAA-MM-JJ`.
///
/// The key is the **local** day: the author writes on their own days.
String dayKeyOf(DateTime moment) {
  final String month = moment.month.toString().padLeft(2, '0');
  final String day = moment.day.toString().padLeft(2, '0');
  return '${moment.year}-$month-$day';
}

/// The local midnight of the day [key] names.
///
/// The answer is `null` when the key is not a day: a corrupted row never
/// reaches the interface.
DateTime? dayOfKey(String key) {
  final List<String> parts = key.split('-');
  if (parts.length != 3) return null;
  final int? year = int.tryParse(parts[0]);
  final int? month = int.tryParse(parts[1]);
  final int? day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}
