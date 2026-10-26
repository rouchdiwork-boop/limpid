import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The state of the dashboard while the library is being read.
///
/// The author sees that the application is working, never a blank page.
class DashboardLoading extends StatelessWidget {
  /// Creates the state.
  const DashboardLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space80),
      child: const Center(child: LimpidSpinner(size: LimpidSpinnerSize.large)),
    );
  }
}

/// The state of the dashboard when the library could not be read.
///
/// The failure is named, the author can try again, and the error itself is
/// never swallowed: it is kept by the provider for the logs.
class DashboardFailure extends StatelessWidget {
  /// Creates the state.
  const DashboardFailure({required this.onRetry, super.key});

  /// Called when the author asks for the library again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: strings.errorGeneric,
        message: strings.dataEmptyMessage,
        action: LimpidButton(
          label: strings.actionRetry,
          icon: LimpidIcons.sync,
          onPressed: onRetry,
        ),
      ),
    );
  }
}

/// The state of the dashboard when the author has no manuscript yet.
class DashboardEmpty extends StatelessWidget {
  /// Creates the state.
  const DashboardEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space32),
      child: LimpidEmptyState(
        title: strings.dataEmptyTitle,
        message: strings.dataEmptyMessage,
      ),
    );
  }
}
