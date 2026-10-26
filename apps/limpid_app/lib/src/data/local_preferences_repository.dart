import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/domain/repositories.dart';

/// The preferences of the author, stored in the local database.
///
/// A preference must never break the interface: every read falls back on a
/// safe value and every write is best effort.
///
/// ## The series of the writing days
///
/// The series of the writing days is read from the **sessions** of the
/// writing — the table that records what the author wrote, day by day.
/// It is never read from the date the scenes were modified: a book that is
/// re-read today was not written today.
///
/// ## The account of the preferences
///
/// The local database is shared by every account of the device: the
/// preferences belong to the account of the session, and the preferences of
/// an author are never shown to another. The account is resolved on every
/// read and every write — a change of account takes effect at once.
final class LocalPreferencesRepository implements PreferencesRepository {
  /// Creates a repository on top of [database].
  ///
  /// The account of the preferences is [accountId] when it is given, and the
  /// account of the session of the device otherwise.
  LocalPreferencesRepository({
    required this.database,
    String Function()? accountId,
    DateTime Function()? now,
  }) : _accountId = accountId ?? (() => database.account.accountId),
       _now = now ?? DateTime.now;

  /// The daily goal of the design system, used when nothing is recorded.
  static const int defaultDailyGoal = 1500;

  /// The key of the daily goal in the table of the preferences.
  static const String dailyGoalKey = 'daily_goal';

  /// The local database of the application.
  final AppDatabase database;

  final String Function() _accountId;
  final DateTime Function() _now;

  @override
  Future<int> dailyGoal() async {
    try {
      final String? raw = await database.manuscripts.readPreference(
        dailyGoalKey,
        accountId: _accountId(),
      );
      final int? words = int.tryParse(raw ?? '');
      if (words == null || words <= 0) return defaultDailyGoal;
      return words;
    } on Object {
      return defaultDailyGoal;
    }
  }

  @override
  Future<void> setDailyGoal(int? words) async {
    if (words == null || words <= 0) return;
    try {
      await database.manuscripts.writePreference(
        dailyGoalKey,
        '$words',
        accountId: _accountId(),
      );
    } on Object {
      // A preference must never break the interface: the previous value is
      // kept when the write fails.
    }
  }

  @override
  Future<int> writingStreak() async {
    try {
      final List<DateTime> days = await database.writingSessions
          .listWritingDays(accountId: _accountId());
      return _streak(days, _now());
    } on Object {
      return 0;
    }
  }

  /// Counts the consecutive days on which the author wrote.
  ///
  /// The days come from the **sessions** of the writing: a day counts when
  /// the author wrote on it, never when they touched a book. Re-reading a
  /// chapter written three weeks ago does not break the series, and does
  /// not start one either.
  ///
  /// The series survives a day that is not over yet: when nothing was
  /// written today, the series of yesterday still counts. A whole day
  /// without writing breaks it.
  static int _streak(List<DateTime> days, DateTime now) {
    final Set<int> written = days.map(_dayOf).toSet();
    int cursor = _dayOf(now);
    if (!written.contains(cursor)) {
      cursor = _dayOf(now.subtract(const Duration(days: 1)));
      if (!written.contains(cursor)) return 0;
    }
    var streak = 0;
    while (written.contains(cursor)) {
      streak++;
      cursor = _dayOf(_previousDay(cursor));
    }
    return streak;
  }

  /// The day before the day of [key].
  static DateTime _previousDay(int key) {
    final DateTime day = DateTime.fromMillisecondsSinceEpoch(key);
    return DateTime(
      day.year,
      day.month,
      day.day,
    ).subtract(const Duration(days: 1));
  }

  /// The day of a moment, as a comparable key.
  static int _dayOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day).millisecondsSinceEpoch;
}
