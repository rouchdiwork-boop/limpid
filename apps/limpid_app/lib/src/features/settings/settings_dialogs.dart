import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/settings/export_file_saver.dart';
import 'package:limpid_app/src/features/settings/settings_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The choice of the author in the export dialog.
sealed class ExportChoice {
  /// Creates a choice.
  const ExportChoice();
}

/// The author asks for the export of the whole personal data.
final class PersonalDataExportChoice extends ExportChoice {
  /// Creates the choice.
  const PersonalDataExportChoice();
}

/// The author asks for the export of a manuscript.
final class ManuscriptExportChoice extends ExportChoice {
  /// Creates the choice.
  const ManuscriptExportChoice(this.project);

  /// The manuscript to export.
  final Project project;
}

/// Lets the author choose the daily rhythm.
///
/// Returns `null` when the author closes the dialog without choosing.
Future<int?> showDailyWordGoalPicker(BuildContext context, int current) {
  final AppLocalizations strings = AppLocalizations.of(context);

  return showDialog<int>(
    context: context,
    builder: (BuildContext dialogContext) {
      return LimpidDialog(
        title: strings.onboardingGoalTitle,
        actions: <Widget>[
          LimpidButton(
            label: strings.actionCancel,
            variant: LimpidButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final int choice in dailyWordGoalChoices)
              LimpidListTile(
                title: _goalLabel(strings, choice),
                subtitle: strings.onboardingGoalWords(choice),
                selected: choice == current,
                onTap: () => Navigator.of(dialogContext).pop(choice),
              ),
          ],
        ),
      );
    },
  );
}

/// Lets the author choose what to export.
///
/// The dialog offers the two exports of the application: the personal data
/// of the account — the RGPD export — and the manuscript of a project.
///
/// Returns `null` when the author closes the dialog without choosing.
Future<ExportChoice?> showDataExportPicker(
  BuildContext context, {
  required List<Project> projects,
  required bool canExportPersonalData,
}) {
  final AppLocalizations strings = AppLocalizations.of(context);

  return showDialog<ExportChoice>(
    context: context,
    builder: (BuildContext dialogContext) {
      return LimpidDialog(
        title: strings.exportTitle,
        actions: <Widget>[
          LimpidButton(
            label: strings.actionCancel,
            variant: LimpidButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LimpidListTile(
              title: strings.settingsExportPersonalData,
              subtitle: canExportPersonalData
                  ? strings.settingsExportPersonalDataSubtitle
                  : strings.settingsExportPersonalDataUnavailable,
              leading: const Icon(LimpidIcons.download),
              onTap: canExportPersonalData
                  ? () => Navigator.of(
                      dialogContext,
                    ).pop(const PersonalDataExportChoice())
                  : null,
            ),
            for (final Project project in projects)
              LimpidListTile(
                title: project.title,
                subtitle: project.synopsis,
                leading: const Icon(LimpidIcons.book),
                onTap: () => Navigator.of(
                  dialogContext,
                ).pop(ManuscriptExportChoice(project)),
              ),
            if (!canExportPersonalData && projects.isEmpty)
              LimpidEmptyState(
                title: strings.dataEmptyTitle,
                message: strings.dataEmptyMessage,
              ),
          ],
        ),
      );
    },
  );
}

/// Shows the file produced by an export.
///
/// The content is displayed as it was produced: the author reads it and
/// copies what they need.
Future<void> showExportPreview(BuildContext context, ExportArtefact artefact) {
  final AppLocalizations strings = AppLocalizations.of(context);
  final LimpidThemeScope scope = context.limpid;
  final String content = utf8.decode(artefact.bytes, allowMalformed: true);

  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return LimpidDialog(
        title: strings.settingsExportPersonalDataReady,
        actions: <Widget>[
          LimpidButton(
            label: strings.actionCancel,
            variant: LimpidButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              artefact.fileName,
              style: LimpidTypography.monoStyle(color: scope.colors.fgMuted),
            ),
            SizedBox(height: scope.spacing.space12),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: LimpidTypography.manuscriptSmallStyle(
                    color: scope.colors.fgDefault,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Shows the export of the personal data and lets the author save it.
///
/// The file is written on the platforms that have a file system and copied in
/// the clipboard on the web.
Future<void> showPersonalDataExport(
  BuildContext context,
  PersonalDataExport export,
) {
  final AppLocalizations strings = AppLocalizations.of(context);
  final LimpidThemeScope scope = context.limpid;
  final String content = utf8.decode(export.bytes, allowMalformed: true);

  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return LimpidDialog(
        title: strings.settingsExportPersonalDataReady,
        actions: <Widget>[
          LimpidButton(
            label: strings.actionCancel,
            variant: LimpidButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          LimpidButton(
            label: strings.exportDownload,
            icon: LimpidIcons.download,
            onPressed: () async {
              await savePersonalDataExport(export);
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              if (!context.mounted) return;
              LimpidSnackbar.show(
                context,
                message: strings.exportReady,
                variant: LimpidStatusVariant.success,
              );
            },
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              export.fileName,
              style: LimpidTypography.monoStyle(color: scope.colors.fgMuted),
            ),
            SizedBox(height: scope.spacing.space12),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: LimpidTypography.manuscriptSmallStyle(
                    color: scope.colors.fgDefault,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Asks the author to confirm the deletion of their account.
///
/// The dialog tells what happens and when the data is purged for good.
/// Returns `true` when the author confirms, `false` otherwise.
Future<bool> showAccountDeletionConfirmation(
  BuildContext context, {
  required DateTime scheduledFor,
}) async {
  final AppLocalizations strings = AppLocalizations.of(context);

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return LimpidDialog(
        title: strings.settingsDeleteAccount,
        actions: <Widget>[
          LimpidButton(
            label: strings.actionCancel,
            variant: LimpidButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          LimpidButton(
            label: strings.settingsDeleteAccount,
            variant: LimpidButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LimpidListTile(
              title: strings.settingsSectionData,
              subtitle: formatDateOf(context, scheduledFor),
              leading: const Icon(LimpidIcons.calendar),
            ),
          ],
        ),
      );
    },
  );

  return confirmed ?? false;
}

/// Tells the author when their account will be purged for good.
///
/// The dialog also tells what happened on the device: the local data of the
/// account is erased when the server accepted the request.
Future<void> showAccountDeletionScheduled(
  BuildContext context,
  AccountDeletion deletion, {
  bool isLocalDataErased = false,
}) {
  final AppLocalizations strings = AppLocalizations.of(context);

  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return LimpidDialog(
        title: strings.settingsDeleteAccountScheduled,
        actions: <Widget>[
          LimpidButton(
            label: strings.actionCancel,
            variant: LimpidButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LimpidListTile(
              title: strings.settingsAccountDeletionDate(
                formatDateOf(context, deletion.scheduledFor),
              ),
              subtitle: formatDateOf(context, deletion.scheduledFor),
              leading: const Icon(LimpidIcons.calendar),
            ),
            if (isLocalDataErased)
              LimpidListTile(
                title: strings.settingsLocalDataErased,
                leading: const Icon(LimpidIcons.check),
              ),
          ],
        ),
      );
    },
  );
}

/// Formats [moment] as the date the author reads.
String formatDateOf(BuildContext context, DateTime moment) {
  final MaterialLocalizations localizations = MaterialLocalizations.of(context);
  return localizations.formatMediumDate(moment);
}

String _goalLabel(AppLocalizations strings, int choice) => switch (choice) {
  lightDailyWordGoal => strings.onboardingGoalLight,
  regularDailyWordGoal => strings.onboardingGoalRegular,
  _ => strings.onboardingGoalIntense,
};
