import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_activity.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_manuscript.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_panels.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_providers.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_states.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_stats.dart';
import 'package:limpid_app/src/features/projects/project_metrics.dart';
import 'package:limpid_app/src/features/projects/project_summary.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_app/src/features/settings/settings_providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The width from which the dashboard is laid out in two columns.
const double _wideLayoutWidth = 860;

/// The dashboard of the author.
///
/// It answers three questions, in this order: what am I working on, where do
/// I stand, how much did I write today. Every figure comes from the
/// repository: the manuscripts of the author, the preferences of the author
/// and the words of their scenes.
class DashboardScreen extends ConsumerWidget {
  /// Creates the screen.
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<LibrarySnapshot> library = ref.watch(libraryProvider);
    final String authorName = ref.watch(authorNameProvider);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.all(scope.spacing.space24),
        children: <Widget>[
          _DashboardHeader(
            title: strings.dashboardTitle,
            subtitle: _greetingOf(strings, authorName),
            onNewProject: () => context.go(AppRoutes.onboarding),
          ),
          SizedBox(height: scope.spacing.space20),
          library.when(
            loading: () => const DashboardLoading(),
            error: (Object error, StackTrace stackTrace) => DashboardFailure(
              onRetry: () => ref.invalidate(libraryProvider),
            ),
            data: (LibrarySnapshot snapshot) => snapshot.projects.isEmpty
                ? const DashboardEmpty()
                : _DashboardContent(snapshot: snapshot),
          ),
        ],
      ),
    );
  }

  /// The greeting of the author.
  ///
  /// The name comes from the session; when nobody is signed in, the interface
  /// greets the author without a name rather than with an invented one.
  static String _greetingOf(AppLocalizations strings, String authorName) =>
      authorName.isEmpty
      ? strings.appTagline
      : strings.dashboardGreeting(authorName);
}

/// The header of the dashboard.
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.title,
    required this.subtitle,
    required this.onNewProject,
  });

  /// The title of the screen.
  final String title;

  /// The line under the title.
  final String subtitle;

  /// Called when the author asks for a new project.
  final VoidCallback onNewProject;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: scope.colors.fgDefault,
                  fontWeight: FontWeight.w600,
                  fontFamily: LimpidFontFamily.display,
                ),
              ),
              SizedBox(height: scope.spacing.space4),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
              ),
            ],
          ),
        ),
        SizedBox(width: scope.spacing.space16),
        LimpidButton(
          label: strings.actionNewProject,
          icon: LimpidIcons.add,
          size: LimpidButtonSize.small,
          onPressed: onNewProject,
        ),
      ],
    );
  }
}

/// The body of the dashboard, once the library is known.
class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.snapshot});

  /// The library of the author.
  final LibrarySnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LimpidThemeScope scope = context.limpid;
    final ProjectSummary? current = ref.watch(currentProjectProvider);
    final int written = ref.watch(wordsWrittenTodayProvider);
    final int goal = ref.watch(dailyGoalProvider).value ?? regularDailyWordGoal;
    final int streak = ref.watch(streakProvider).value ?? 0;
    final int weeklyWords = ref.watch(writingActivityProvider).weeklyWords;
    final String authorName = ref.watch(authorNameProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DashboardStats(
          written: written,
          goal: goal,
          streak: streak,
          weeklyWords: weeklyWords,
          manuscript: current,
        ),
        SizedBox(height: scope.spacing.space20),
        LayoutBuilder(
          builder: (context, constraints) {
            final bool isWide = constraints.maxWidth >= _wideLayoutWidth;
            final Widget main = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (current != null)
                  DashboardManuscript(project: current, authorName: authorName),
                SizedBox(height: scope.spacing.space20),
                const DashboardActivity(),
              ],
            );
            final Widget side = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DashboardGoalPanel(written: written),
                SizedBox(height: scope.spacing.space20),
                const DashboardTodoPanel(),
              ],
            );

            if (!isWide) {
              return Column(
                children: <Widget>[
                  main,
                  SizedBox(height: scope.spacing.space20),
                  side,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 55, child: main),
                SizedBox(width: scope.spacing.space20),
                Expanded(flex: 35, child: side),
              ],
            );
          },
        ),
      ],
    );
  }
}
