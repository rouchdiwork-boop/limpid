import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The state of the library while the manuscripts are being read.
class LibraryLoading extends StatelessWidget {
  /// Creates the state.
  const LibraryLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space80),
      child: const Center(child: LimpidSpinner(size: LimpidSpinnerSize.large)),
    );
  }
}

/// The state of the library when the manuscripts could not be read.
class LibraryFailure extends StatelessWidget {
  /// Creates the state.
  const LibraryFailure({required this.onRetry, super.key});

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

/// The state of the library when the author has no manuscript yet.
class LibraryEmpty extends StatelessWidget {
  /// Creates the state.
  const LibraryEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space32),
      child: LimpidEmptyState(
        title: strings.dataEmptyTitle,
        message: strings.dataEmptyMessage,
        action: LimpidButton(
          label: strings.actionNewProject,
          icon: LimpidIcons.add,
        ),
      ),
    );
  }
}

/// The state of the library when the filter matches no manuscript.
class LibraryFilterEmpty extends StatelessWidget {
  /// Creates the state.
  const LibraryFilterEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space32),
      child: LimpidEmptyState(
        title: strings.libraryEmptyTitle,
        message: strings.libraryEmptyMessage,
        action: LimpidButton(
          label: strings.actionNewProject,
          icon: LimpidIcons.add,
        ),
      ),
    );
  }
}
