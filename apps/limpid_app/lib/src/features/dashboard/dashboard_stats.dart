import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_app/src/features/projects/project_summary.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The row of the figures of the dashboard.
///
/// Every figure comes from the repository: the words written today, the
/// series of the writing days, the manuscript the author is working on and
/// the words of the last seven days.
class DashboardStats extends StatelessWidget {
  /// Creates the row.
  const DashboardStats({
    required this.written,
    required this.goal,
    required this.streak,
    required this.weeklyWords,
    required this.manuscript,
    super.key,
  });

  /// The number of words written today.
  final int written;

  /// The number of words the author aims to write every day.
  final int goal;

  /// The number of consecutive days on which the author wrote.
  final int streak;

  /// The number of words written during the last seven days.
  final int weeklyWords;

  /// The manuscript the author is working on.
  final ProjectSummary? manuscript;

  /// The ratio of the card when the dashboard is a single column.
  static const double _narrowCardRatio = 3.4;

  /// The ratio of the card when the dashboard has several columns.
  static const double _wideCardRatio = 1.9;

  /// The width from which the figures are laid out in four columns.
  static const double _fourColumnsWidth = 900;

  /// The width from which the figures are laid out in two columns.
  static const double _twoColumnsWidth = 560;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final int percent = goal <= 0 ? 0 : (written * 100 / goal).round();
    final ProjectSummary? current = manuscript;

    return LayoutBuilder(
      builder: (context, constraints) {
        final int columns = constraints.maxWidth >= _fourColumnsWidth
            ? 4
            : constraints.maxWidth >= _twoColumnsWidth
            ? 2
            : 1;

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: scope.spacing.space16,
          crossAxisSpacing: scope.spacing.space16,
          childAspectRatio: columns == 1 ? _narrowCardRatio : _wideCardRatio,
          children: <Widget>[
            LimpidStatCard(
              label: strings.dashboardTodayWords,
              value: formatCount(written),
              caption: strings.dashboardGoalOf(formatCount(goal), '$percent'),
            ),
            LimpidStatCard(
              label: strings.dashboardStreak,
              value: '$streak',
              caption: strings.dashboardStreakUnit,
            ),
            LimpidStatCard(
              label: strings.dashboardManuscript,
              value: formatCount(current?.wordCount ?? 0),
              caption: current == null ? null : '${current.progressPercent} %',
            ),
            LimpidStatCard(
              label: strings.dashboardWeeklyWords,
              value: formatCount(weeklyWords),
            ),
          ],
        );
      },
    );
  }
}
