/// The writing goals of an author (P1 / P2).
final class WritingGoal {
  /// Creates a goal description.
  const WritingGoal({
    this.dailyWordTarget = 0,
    this.projectWordTarget = 0,
    this.sceneWordTarget = 0,
  });

  /// The number of words targeted per day.
  final int dailyWordTarget;

  /// The number of words targeted for the whole project.
  final int projectWordTarget;

  /// The number of words targeted for the current scene.
  final int sceneWordTarget;

  /// Whether the goal defines no target at all.
  bool get isEmpty =>
      dailyWordTarget == 0 && projectWordTarget == 0 && sceneWordTarget == 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WritingGoal &&
          other.dailyWordTarget == dailyWordTarget &&
          other.projectWordTarget == projectWordTarget &&
          other.sceneWordTarget == sceneWordTarget);

  @override
  int get hashCode => Object.hash(
    WritingGoal,
    dailyWordTarget,
    projectWordTarget,
    sceneWordTarget,
  );

  @override
  String toString() =>
      'WritingGoal(daily: $dailyWordTarget, project: $projectWordTarget)';
}

/// The status of a goal compared to the words actually written.
final class GoalStatus {
  /// Creates a goal status.
  const GoalStatus({
    required this.writtenWords,
    required this.targetWords,
    required this.ratio,
    required this.isReached,
  });

  /// The number of words written.
  final int writtenWords;

  /// The number of words targeted.
  final int targetWords;

  /// The completion ratio, in `[0, 1]`.
  final double ratio;

  /// Whether the target was reached.
  final bool isReached;

  /// The number of words still missing, `0` when the target is reached.
  int get remainingWords {
    final remaining = targetWords - writtenWords;
    return remaining > 0 ? remaining : 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoalStatus &&
          other.writtenWords == writtenWords &&
          other.targetWords == targetWords &&
          other.ratio == ratio &&
          other.isReached == isReached);

  @override
  int get hashCode =>
      Object.hash(GoalStatus, writtenWords, targetWords, ratio, isReached);

  @override
  String toString() =>
      'GoalStatus($writtenWords/$targetWords, reached: $isReached)';
}

/// Evaluates the writing goals and the writing streak of an author.
final class GoalEvaluator {
  /// Creates a goal evaluator.
  const GoalEvaluator();

  /// Evaluates the daily goal.
  GoalStatus evaluateDaily({
    required int writtenWords,
    required int dailyWordTarget,
  }) {
    return _status(writtenWords, dailyWordTarget);
  }

  /// Evaluates the goal of a project.
  GoalStatus evaluateProject({
    required int writtenWords,
    required int projectWordTarget,
  }) {
    return _status(writtenWords, projectWordTarget);
  }

  /// Evaluates the goal of a scene.
  GoalStatus evaluateScene({
    required int writtenWords,
    required int sceneWordTarget,
  }) {
    return _status(writtenWords, sceneWordTarget);
  }

  /// Counts the consecutive days of writing ending on [today].
  ///
  /// [writingDays] holds every day the author wrote something. The streak
  /// starts at [today] (or the closest earlier writing day when today is
  /// still empty) and counts backwards.
  int evaluateStreak({
    required Iterable<DateTime> writingDays,
    required DateTime today,
  }) {
    final days = <DateTime>{};
    for (final day in writingDays) {
      days.add(_dayOf(day));
    }
    final reference = _dayOf(today);
    var cursor = reference;
    if (!days.contains(cursor)) {
      cursor = reference.subtract(const Duration(days: 1));
      if (!days.contains(cursor)) return 0;
    }
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  GoalStatus _status(int writtenWords, int targetWords) {
    if (targetWords <= 0) {
      return GoalStatus(
        writtenWords: writtenWords,
        targetWords: 0,
        ratio: 0,
        isReached: false,
      );
    }
    final ratio = (writtenWords / targetWords).clamp(0.0, 1.0);
    return GoalStatus(
      writtenWords: writtenWords,
      targetWords: targetWords,
      ratio: ratio,
      isReached: writtenWords >= targetWords,
    );
  }

  DateTime _dayOf(DateTime date) => DateTime(date.year, date.month, date.day);
}
