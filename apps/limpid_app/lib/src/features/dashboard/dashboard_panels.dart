import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The panel of the daily goal of the author.
///
/// The goal comes from the preferences of the author, the words written today
/// come from the scenes of the library.
class DashboardGoalPanel extends ConsumerWidget {
  /// Creates the panel.
  const DashboardGoalPanel({required this.written, super.key});

  /// The number of words written today.
  final int written;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<int> goal = ref.watch(dailyGoalProvider);
    final int? target = goal.value;

    return LimpidCard(
      title: strings.dashboardGoalTitle,
      subtitle: target == null
          ? null
          : '${formatCount(written)} / ${formatCount(target)} '
                '${strings.commonWords}',
      child: Padding(
        padding: EdgeInsets.only(top: scope.spacing.space16),
        child: goal.when(
          loading: () => const _PanelLoading(),
          error: (Object error, StackTrace stackTrace) =>
              _PanelFailure(onRetry: () => ref.invalidate(dailyGoalProvider)),
          data: (int value) => _GoalProgress(written: written, goal: value),
        ),
      ),
    );
  }
}

/// The progress of the daily goal.
class _GoalProgress extends StatelessWidget {
  const _GoalProgress({required this.written, required this.goal});

  /// The number of words written today.
  final int written;

  /// The number of words the author aims to write every day.
  final int goal;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final int remaining = (goal - written).clamp(0, goal);
    final int percent = goal <= 0 ? 0 : (written * 100 / goal).round();
    final int minutes = const ReadingTimeEstimator()
        .estimate(remaining)
        .inMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LimpidLinearProgress(value: percent / 100),
        SizedBox(height: scope.spacing.space8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              strings.dashboardRemaining(formatCount(remaining)),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scope.colors.fgMuted),
            ),
            Text(
              strings.dashboardAboutMinutes(minutes),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scope.colors.fgSubtle),
            ),
          ],
        ),
      ],
    );
  }
}

/// The panel of the tasks of the author.
///
/// The interface has no store of tasks yet: the panel tells the truth, it
/// shows that there is nothing to do and offers to add one.
class DashboardTodoPanel extends StatelessWidget {
  /// Creates the panel.
  const DashboardTodoPanel({super.key});

  /// The number of tasks the interface knows about.
  static const int taskCount = 0;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return LimpidCard(
      title: strings.dashboardTodoTitle,
      trailing: LimpidBadge(label: formatCount(taskCount)),
      child: Padding(
        padding: EdgeInsets.only(top: scope.spacing.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              strings.dashboardTodoEmpty,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scope.colors.fgDefault),
            ),
            SizedBox(height: scope.spacing.space16),
            LimpidButton(
              label: strings.dashboardAddTask,
              variant: LimpidButtonVariant.ghost,
              size: LimpidButtonSize.small,
            ),
          ],
        ),
      ),
    );
  }
}

/// The busy state of a panel.
class _PanelLoading extends StatelessWidget {
  const _PanelLoading();

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space12),
      child: const Align(
        alignment: Alignment.centerLeft,
        child: LimpidSpinner(size: LimpidSpinnerSize.medium),
      ),
    );
  }
}

/// The failure of a panel.
class _PanelFailure extends StatelessWidget {
  const _PanelFailure({required this.onRetry});

  /// Called when the author asks for the figures again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            strings.errorGeneric,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scope.colors.danger),
          ),
          SizedBox(height: scope.spacing.space8),
          LimpidButton(
            label: strings.actionRetry,
            variant: LimpidButtonVariant.ghost,
            size: LimpidButtonSize.small,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
