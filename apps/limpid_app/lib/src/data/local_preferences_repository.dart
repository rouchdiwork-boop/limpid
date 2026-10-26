import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/domain/repositories.dart';

/// The preferences of the author, stored in the local database.
///
/// A preference must never break the interface: every read falls back on a
/// safe value and every write is best effort.
final class LocalPreferencesRepository implements PreferencesRepository {
  /// Creates a repository on top of [database].
  LocalPreferencesRepository({required this.database, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// The daily goal of the design system, used when nothing is recorded.
  static const int defaultDailyGoal = 1500;

  /// The key of the daily goal in the table of the preferences.
  static const String dailyGoalKey = 'daily_goal';

  /// The local database of the application.
  final AppDatabase database;

  final DateTime Function() _now;

  @override
  Future<int> dailyGoal() async {
    try {
      final String? raw = await database.manuscripts.readPreference(
        dailyGoalKey,
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
      await database.manuscripts.writePreference(dailyGoalKey, '$words');
    } on Object {
      // A preference must never break the interface: the previous value is
      // kept when the write fails.
    }
  }

  @override
  Future<int> writingStreak() async {
    try {
      final List<DateTime> days = await database.manuscripts.listWritingDays();
      return _streak(days, _now());
    } on Object {
      return 0;
    }
  }

  /// Counts the consecutive days on which the author wrote.
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
