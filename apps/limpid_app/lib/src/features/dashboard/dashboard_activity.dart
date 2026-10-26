import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_providers.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The activity of the writing of the author, over the last twelve weeks.
///
/// The grid shows the weeks in their columns and the days in their rows: the
/// figures come from the scenes of the library.
class DashboardActivity extends ConsumerWidget {
  /// Creates the card.
  const DashboardActivity({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final MaterialLocalizations dates = MaterialLocalizations.of(context);
    final WritingActivity activity = ref.watch(writingActivityProvider);

    return LimpidCard(
      title: strings.dashboardActivityTitle,
      child: Padding(
        padding: EdgeInsets.only(top: scope.spacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ActivityGrid(activity: activity),
            SizedBox(height: scope.spacing.space12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  dates.formatShortDate(activity.firstDay),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scope.colors.fgSubtle,
                  ),
                ),
                Text(
                  dates.formatShortDate(activity.lastDay),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scope.colors.fgSubtle,
                  ),
                ),
              ],
            ),
            SizedBox(height: scope.spacing.space16),
            _ActivitySummary(activity: activity),
          ],
        ),
      ),
    );
  }
}

/// The grid of the days of the activity.
class _ActivityGrid extends StatelessWidget {
  const _ActivityGrid({required this.activity});

  /// The activity the grid shows.
  final WritingActivity activity;

  /// The number of days in a week.
  static const int _daysPerWeek = 7;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final int highest = activity.counts.fold<int>(
      0,
      (int best, int count) => count > best ? count : best,
    );

    return Semantics(
      label: AppLocalizations.of(
        context,
      ).libraryWords(formatCount(activity.totalWords)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int column = 0; column < activityWeeks; column++)
            Expanded(
              child: Column(
                children: <Widget>[
                  for (int row = 0; row < _daysPerWeek; row++)
                    Padding(
                      padding: EdgeInsets.all(scope.spacing.space2),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: _ActivityCell(
                          level: _levelOf(
                            activity.wordsAt(column * _daysPerWeek + row),
                            highest,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The level of a day, between 0 and 4.
  ///
  /// The levels are relative to the best day of the period: a day without
  /// writing stays at the lowest level.
  static int _levelOf(int words, int highest) {
    if (words <= 0 || highest <= 0) return 0;
    final double ratio = words / highest;
    if (ratio <= 0.25) return 1;
    if (ratio <= 0.5) return 2;
    if (ratio < 1) return 3;
    return 4;
  }
}

/// A day of the activity.
class _ActivityCell extends StatelessWidget {
  const _ActivityCell({required this.level});

  /// The level of the day, between 0 and 4.
  final int level;

  /// The share of the accent of the first level.
  static const double _firstLevel = 0.28;

  /// The share of the accent of the second level.
  static const double _secondLevel = 0.52;

  /// The share of the accent of the third level.
  static const double _thirdLevel = 0.76;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final LimpidColors colors = scope.colors;
    final Color accent = colors.accent;
    final Color background = switch (level) {
      0 => colors.bgSunken,
      1 => Color.lerp(colors.bgSunken, accent, _firstLevel)!,
      2 => Color.lerp(colors.bgSunken, accent, _secondLevel)!,
      3 => Color.lerp(colors.bgSunken, accent, _thirdLevel)!,
      _ => accent,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(scope.radii.xs),
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// The figures of the last week.
class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.activity});

  /// The activity the figures come from.
  final WritingActivity activity;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final MaterialLocalizations dates = MaterialLocalizations.of(context);
    final int? best = activity.bestDayIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SummaryLine(
          label: strings.dashboardWeeklyWords,
          value: strings.libraryWords(formatCount(activity.weeklyWords)),
        ),
        if (best != null)
          _SummaryLine(
            label: strings.dashboardBestDay,
            value:
                '${dates.formatShortDate(activity.firstDay.add(Duration(days: best)))}'
                ' · ${strings.libraryWords(formatCount(activity.wordsAt(best)))}',
          ),
      ],
    );
  }
}

/// A figure of the activity, with its label.
class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  /// The name of the figure.
  final String label;

  /// The value of the figure.
  final String value;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.only(bottom: scope.spacing.space6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scope.colors.fgDefault),
          ),
        ],
      ),
    );
  }
}
