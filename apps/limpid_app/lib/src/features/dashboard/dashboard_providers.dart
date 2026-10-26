import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/auth/session_controller.dart';
import 'package:limpid_app/src/features/projects/project_metrics.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_core/limpid_core.dart';

/// The number of weeks the activity of the writing covers.
const int activityWeeks = 12;

/// The number of days the activity of the writing covers.
const int activityDays = activityWeeks * 7;

/// The number of days the weekly figures cover.
const int activityWeekDays = 7;

/// The activity of the writing of the author, day by day.
///
/// The first day of the activity is a Monday: the grid of the dashboard
/// shows the weeks in their columns and the days in their rows.
@immutable
class WritingActivity {
  /// Creates an activity.
  const WritingActivity({required this.firstDay, required this.counts});

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

/// The activity of the writing of the author.
///
/// The figures come from the scenes of the library: a scene carries the day
/// it was written on and the number of words it holds.
final writingActivityProvider = Provider<WritingActivity>((ref) {
  final List<Scene> scenes =
      ref.watch(libraryProvider).value?.scenes ?? const <Scene>[];
  final DateTime today = ref.watch(todayProvider).toUtc();
  final DateTime day = DateTime.utc(today.year, today.month, today.day);
  final DateTime firstDay = day.subtract(
    Duration(days: (activityWeeks - 1) * 7 + day.weekday - 1),
  );
  final int days = daysBetween(firstDay, day) + 1;

  return WritingActivity(
    firstDay: firstDay,
    counts: dailyWordCounts(scenes, firstDay, days),
  );
});

/// The public name of the author, read from the session.
///
/// The name is empty when nobody is signed in: the interface then greets the
/// author without a name, never with a name it invented.
final authorNameProvider = Provider<String>((ref) {
  final session = ref.watch(sessionControllerProvider).value;
  return session?.authorName ?? session?.email ?? '';
});
