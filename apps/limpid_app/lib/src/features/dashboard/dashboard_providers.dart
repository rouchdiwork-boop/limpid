import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/auth/session_controller.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';

/// The number of weeks the activity of the writing covers.
const int activityWeeks = 12;

/// The number of days the activity of the writing covers.
const int activityDays = activityWeeks * 7;

/// The number of days the weekly figures cover.
const int activityWeekDays = 7;

/// The number of days the history of the writing covers.
const int historyDays = 14;

/// The activity of the writing of the author, day by day.
///
/// The first day of the activity is a Monday: the grid of the dashboard
/// shows the weeks in their columns and the days in their rows.
@immutable
class WritingActivity {
  /// Creates an activity.
  const WritingActivity({required this.firstDay, required this.counts});

  /// An activity that carries no writing.
  ///
  /// The activity is empty while the sessions are read: the grid shows an
  /// empty period rather than a figure it invented.
  factory WritingActivity.empty(DateTime firstDay) =>
      WritingActivity(firstDay: firstDay, counts: const <int>[]);

  /// The first day of the activity, a Monday.
  final DateTime firstDay;

  /// The number of words written on each day of the activity.
  final List<int> counts;

  /// The last day of the activity.
  DateTime get lastDay => firstDay.add(Duration(days: counts.length - 1));

  /// The total number of words of the activity.
  int get totalWords =>
      counts.fold<int>(0, (int total, int count) => total + count);

  /// The number of words written during the last seven days.
  int get weeklyWords {
    if (counts.isEmpty) return 0;
    final int from = counts.length > activityWeekDays
        ? counts.length - activityWeekDays
        : 0;
    int total = 0;
    for (int index = from; index < counts.length; index++) {
      total += counts[index];
    }
    return total;
  }

  /// The day of the last week that carried the most words.
  ///
  /// The index is relative to the first day of the activity; it is `null`
  /// when no word was written during the last week.
  int? get bestDayIndex {
    if (counts.isEmpty) return null;
    final int from = counts.length > activityWeekDays
        ? counts.length - activityWeekDays
        : 0;
    int best = from;
    for (int index = from; index < counts.length; index++) {
      if (counts[index] > counts[best]) best = index;
    }
    if (counts[best] <= 0) return null;
    return best;
  }

  /// The number of words written on the day at [index].
  int wordsAt(int index) =>
      index < 0 || index >= counts.length ? 0 : counts[index];
}

/// The writing sessions of the author, the most recent day first.
///
/// The sessions come from the device: they record what the author wrote,
/// day by day. They never come from the date the scenes were modified —
/// re-reading a book is not writing.
final writingSessionsProvider = FutureProvider<List<WritingSession>>((
  Ref ref,
) async {
  final ManuscriptRepository repository = ref.watch(
    manuscriptRepositoryProvider,
  );
  if (repository is! WritingSessionRepository) return const <WritingSession>[];
  final DateTime today = localDayOf(ref.watch(todayProvider));
  return repository.writingSessions(
    from: dayBefore(today, historyDays - 1),
    to: today,
  );
});

/// The activity of the writing of the author.
///
/// The figures come from the **sessions** of the writing: the days on which
/// the author wrote, and the words they wrote that day.
final writingActivityProvider = FutureProvider<WritingActivity>((ref) async {
  final ManuscriptRepository repository = ref.watch(
    manuscriptRepositoryProvider,
  );
  final DateTime today = localDayOf(ref.watch(todayProvider));
  final DateTime firstDay = firstActivityDay(today);
  final int days = daysBetween(firstDay, today) + 1;
  final List<WritingSession> sessions = repository is WritingSessionRepository
      ? await repository.writingSessions(from: firstDay, to: today)
      : const <WritingSession>[];
  return WritingActivity(
    firstDay: firstDay,
    counts: countsOf(sessions, firstDay, days),
  );
});

/// The number of words written on each of the [days] days that start on
/// [first].
///
/// The list is ordered from the oldest day to the most recent one.
List<int> countsOf(List<WritingSession> sessions, DateTime first, int days) {
  final List<int> counts = List<int>.filled(days, 0);
  if (days <= 0) return counts;
  for (final WritingSession session in sessions) {
    final int index = daysBetween(first, session.day);
    if (index < 0 || index >= days) continue;
    counts[index] += session.words;
  }
  return counts;
}

/// The local day of [moment].
///
/// The day of the author is **local**: the sessions of the writing are keyed
/// by the local day, and the figures of the dashboard must be read on the
/// same days.
DateTime localDayOf(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// The day [days] before the day of [moment].
///
/// The arithmetic is done on the days, not on the instants: a daylight
/// saving change never moves a day.
DateTime dayBefore(DateTime moment, int days) {
  final DateTime shifted = DateTime.utc(
    moment.year,
    moment.month,
    moment.day,
  ).subtract(Duration(days: days));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// The first day of the activity: the Monday of the week of [moment], twelve
/// weeks earlier.
///
/// The activity covers the [activityWeeks] weeks that end today: the grid
/// shows a column per week, and the oldest column is the first one.
DateTime firstActivityDay(DateTime moment) {
  final DateTime shifted = DateTime.utc(
    moment.year,
    moment.month,
    moment.day,
  ).subtract(Duration(days: moment.weekday - 1));
  final DateTime monday = DateTime(shifted.year, shifted.month, shifted.day);
  return dayBefore(monday, (activityWeeks - 1) * 7);
}

/// The number of days between two days, the first one included.
///
/// The days are compared as **calendar days**: the hour of a day never
/// changes the answer.
int daysBetween(DateTime first, DateTime last) => DateTime.utc(
  last.year,
  last.month,
  last.day,
).difference(DateTime.utc(first.year, first.month, first.day)).inDays;

/// The public name of the author, read from the session.
///
/// The name is empty when nobody is signed in: the interface then greets the
/// author without a name, never with a name it invented.
final authorNameProvider = Provider<String>((ref) {
  final session = ref.watch(sessionControllerProvider).value;
  return session?.authorName ?? session?.email ?? '';
});
