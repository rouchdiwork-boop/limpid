import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/settings/gdpr_providers.dart';
import 'package:limpid_app/src/features/settings/local_data_erasure.dart';
import 'package:limpid_app/src/features/settings/settings_dialogs.dart';
import 'package:limpid_app/src/features/settings/settings_providers.dart';
import 'package:limpid_app/src/features/settings/settings_sections.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The section of the personal data of the author.
///
/// The section owns the two obligations of the RGPD (D-19): the export of the
/// personal data and the deletion of the account. The actions are long, so
/// they live in their own file and the screen stays a screen.
class SettingsDataSection extends ConsumerWidget {
  /// Creates the section.
  const SettingsDataSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final AsyncValue<List<Project>> library = ref.watch(
      libraryProjectsProvider,
    );
    final ExportRepository exportRepository = ref.watch(
      exportRepositoryProvider,
    );
    final List<Project> projects = library.value ?? const <Project>[];
    final bool isManuscriptAvailable = exportRepository is! UnavailableService;
    final bool hasProjects = library.hasValue && projects.isNotEmpty;
    final GdprRepository gdpr = ref.watch(gdprRepositoryProvider);
    final bool isAccountAvailable = gdpr is! UnavailableService;
    final bool isExporting = ref.watch(personalDataExportProvider).isRunning;
    final bool isDeleting = ref.watch(accountDeletionProvider).isRunning;

    return SettingsSection(
      title: strings.settingsSectionData,
      children: <Widget>[
        LimpidListTile(
          title: strings.settingsExportPersonalData,
          subtitle: _subtitle(
            strings: strings,
            isAccountAvailable: isAccountAvailable,
            isManuscriptAvailable: isManuscriptAvailable,
            hasProjects: hasProjects,
          ),
          leading: isExporting
              ? const LimpidSpinner()
              : const Icon(LimpidIcons.download),
          onTap: isAccountAvailable || (isManuscriptAvailable && hasProjects)
              ? () => _exportData(context, ref, projects)
              : null,
        ),
        LimpidListTile(
          title: strings.settingsDeleteAccount,
          subtitle: isAccountAvailable
              ? formatDateOf(context, _deletionDate())
              : strings.settingsAccountDeletionUnavailable,
          leading: isDeleting
              ? const LimpidSpinner()
              : const Icon(LimpidIcons.delete),
          onTap: isAccountAvailable ? () => _deleteAccount(context, ref) : null,
        ),
      ],
    );
  }

  /// The line below the export row.
  ///
  /// The row opens the dialog of the exports: it offers the personal data of
  /// the account and the manuscripts. The line says what the application can
  /// really do — and says nothing when it can do nothing.
  String _subtitle({
    required AppLocalizations strings,
    required bool isAccountAvailable,
    required bool isManuscriptAvailable,
    required bool hasProjects,
  }) {
    if (!isAccountAvailable && !isManuscriptAvailable) {
      return strings.settingsExportPersonalDataUnavailable;
    }
    if (isAccountAvailable) {
      return strings.settingsExportPersonalDataSubtitle;
    }
    if (hasProjects) {
      return strings.settingsExportManuscriptsSubtitle;
    }
    return strings.dataEmptyMessage;
  }

  Future<void> _exportData(
    BuildContext context,
    WidgetRef ref,
    List<Project> projects,
  ) async {
    final bool isAccountAvailable =
        ref.read(gdprRepositoryProvider) is! UnavailableService;
    final ExportChoice? choice = await showDataExportPicker(
      context,
      projects: projects,
      canExportPersonalData: isAccountAvailable,
    );
    if (choice == null || !context.mounted) {
      return;
    }
    switch (choice) {
      case PersonalDataExportChoice():
        await _exportPersonalData(context, ref);
      case ManuscriptExportChoice(:final Project project):
        await _exportProject(context, ref, project);
    }
  }

  Future<void> _exportPersonalData(BuildContext context, WidgetRef ref) async {
    final AppLocalizations strings = AppLocalizations.of(context);
    try {
      final PersonalDataExport? result = await ref
          .read(personalDataExportProvider.notifier)
          .export();
      if (result == null || !context.mounted) {
        return;
      }
      await showPersonalDataExport(context, result);
    } on ServiceUnavailableException {
      if (!context.mounted) {
        return;
      }
      _showError(
        context,
        strings.settingsExportPersonalDataUnavailable,
        LimpidStatusVariant.warning,
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error.message, LimpidStatusVariant.danger);
    } on Exception {
      if (!context.mounted) {
        return;
      }
      _showError(
        context,
        strings.settingsExportPersonalDataFailed,
        LimpidStatusVariant.danger,
      );
    }
  }

  Future<void> _exportProject(
    BuildContext context,
    WidgetRef ref,
    Project project,
  ) async {
    final AppLocalizations strings = AppLocalizations.of(context);
    try {
      final ExportArtefact artefact = await ref
          .read(exportRepositoryProvider)
          .export(projectId: project.id.value, format: ExportFormat.markdown);
      if (!context.mounted) {
        return;
      }
      await showExportPreview(context, artefact);
    } on ServiceUnavailableException {
      if (!context.mounted) {
        return;
      }
      _showError(
        context,
        strings.settingsExportPersonalDataUnavailable,
        LimpidStatusVariant.warning,
      );
    } on Exception {
      if (!context.mounted) {
        return;
      }
      _showError(context, strings.exportFailed, LimpidStatusVariant.danger);
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final AppLocalizations strings = AppLocalizations.of(context);
    final bool confirmed = await showAccountDeletionConfirmation(
      context,
      scheduledFor: _deletionDate(),
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      final AccountDeletion? deletion = await ref
          .read(accountDeletionProvider.notifier)
          .requestDeletion();
      if (deletion == null || !context.mounted) {
        return;
      }
      // Le serveur a accepté la demande : les données locales du compte
      // sont effacées de ce poste, puis la session est fermée. L'effacement
      // vient **après** l'acceptation du serveur : l'auteur ne perd jamais
      // son manuscrit tant que le serveur garde son compte.
      final LocalDataErasure outcome = await eraseLocalData(ref);
      if (!context.mounted) {
        return;
      }
      if (outcome != LocalDataErasure.erased) {
        showLocalDataErasureFailure(context, outcome);
      }
      await showAccountDeletionScheduled(
        context,
        deletion,
        isLocalDataErased: outcome == LocalDataErasure.erased,
      );
      if (!context.mounted) {
        return;
      }
      await closeSession(context, ref);
    } on ServiceUnavailableException {
      if (!context.mounted) {
        return;
      }
      _showError(
        context,
        strings.settingsExportPersonalDataUnavailable,
        LimpidStatusVariant.warning,
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      _showError(context, error.message, LimpidStatusVariant.danger);
    } on Exception {
      if (!context.mounted) {
        return;
      }
      _showError(
        context,
        strings.settingsExportPersonalDataFailed,
        LimpidStatusVariant.danger,
      );
    }
  }

  /// The day the data of the account is purged for good (D-19).
  DateTime _deletionDate() => DateTime.now().toUtc().add(
    const Duration(days: accountDeletionRetentionDays),
  );

  void _showError(
    BuildContext context,
    String message,
    LimpidStatusVariant variant,
  ) {
    LimpidSnackbar.show(context, message: message, variant: variant);
  }
}
