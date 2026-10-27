import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/app/theme_controller.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/session_controller.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';
import 'package:limpid_app/src/features/settings/local_data_erasure.dart';
import 'package:limpid_app/src/features/settings/settings_data_section.dart';
import 'package:limpid_app/src/features/settings/settings_dialogs.dart';
import 'package:limpid_app/src/features/settings/settings_privacy_section.dart';
import 'package:limpid_app/src/features/settings/settings_providers.dart';
import 'package:limpid_app/src/features/settings/settings_sections.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The settings of the author.
///
/// Every row reads the real state of the application: the identity comes
/// from the session, the theme from the theme controller, the
/// synchronisation from the sync repository. The actions that the backend
/// does not support yet are disabled and say why.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AuthSession? session = ref.watch(sessionControllerProvider).value;
    final LimpidThemeVariant variant = ref.watch(themeControllerProvider);
    final SyncStatus status =
        ref.watch(syncStatusProvider).value ??
        ref.read(syncRepositoryProvider).status;
    final int pending = ref.watch(pendingSyncCountProvider);
    final SyncActionState syncAction = ref.watch(syncActionProvider);
    final int goal = ref.watch(dailyWordGoalProvider);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.all(scope.spacing.space24),
        children: <Widget>[
          Text(
            strings.settingsTitle,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: scope.colors.fgDefault,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: scope.spacing.space20),
          _buildProfile(context, session),
          SizedBox(height: scope.spacing.space16),
          _buildTheme(context, ref, variant),
          SizedBox(height: scope.spacing.space16),
          _buildEditor(context, ref, goal),
          SizedBox(height: scope.spacing.space16),
          _buildSync(context, ref, status, pending, syncAction),
          SizedBox(height: scope.spacing.space16),
          _buildSecurity(context, strings),
          SizedBox(height: scope.spacing.space16),
          const SettingsPrivacySection(),
          SizedBox(height: scope.spacing.space16),
          _buildDevices(context),
          SizedBox(height: scope.spacing.space16),
          const SettingsDataSection(),
          SizedBox(height: scope.spacing.space24),
          LimpidButton(
            label: strings.actionSignOut,
            variant: LimpidButtonVariant.secondary,
            icon: LimpidIcons.arrowLeft,
            expand: true,
            onPressed: () => _signOut(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _buildProfile(BuildContext context, AuthSession? session) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final String name =
        session?.authorName ?? session?.email ?? strings.navAccount;
    final String detail = session == null
        ? strings.signInSubtitle
        : strings.settingsSignedInAs(session.email);

    return SettingsSection(
      title: strings.settingsSectionProfile,
      children: <Widget>[
        LimpidListTile(
          title: name,
          subtitle: detail,
          leading: LimpidAvatar(label: name),
        ),
      ],
    );
  }

  Widget _buildTheme(
    BuildContext context,
    WidgetRef ref,
    LimpidThemeVariant variant,
  ) {
    final AppLocalizations strings = AppLocalizations.of(context);

    return SettingsSection(
      title: strings.settingsTheme,
      children: <Widget>[
        for (final MapEntry<LimpidThemeVariant, String> entry
            in <LimpidThemeVariant, String>{
              LimpidThemeVariant.paper: strings.settingsThemePaper,
              LimpidThemeVariant.sepia: strings.settingsThemeSepia,
              LimpidThemeVariant.night: strings.settingsThemeNight,
              LimpidThemeVariant.contrast: strings.settingsThemeContrast,
            }.entries)
          ThemeVariantRow(
            label: entry.value,
            variant: entry.key,
            isSelected: entry.key == variant,
            onTap: () =>
                ref.read(themeControllerProvider.notifier).select(entry.key),
          ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context, WidgetRef ref, int goal) {
    final AppLocalizations strings = AppLocalizations.of(context);

    return SettingsSection(
      title: strings.settingsSectionEditor,
      children: <Widget>[
        LimpidListTile(
          title: strings.onboardingGoalTitle,
          subtitle: strings.onboardingGoalWords(goal),
          leading: const Icon(LimpidIcons.target),
          onTap: () => _pickGoal(context, ref),
        ),
      ],
    );
  }

  /// The integrations of the account: the second factor, the API keys and
  /// the outgoing webhooks.
  ///
  /// They live together because they answer the same question — how does a
  /// program talk to this account — and because they share the same
  /// guards: a key and a webhook are useless without the second factor.
  Widget _buildSecurity(BuildContext context, AppLocalizations strings) {
    return SettingsSection(
      title: strings.settingsSectionSecurity,
      children: <Widget>[
        LimpidListTile(
          title: strings.twoFactorTitle,
          subtitle: strings.twoFactorSubtitle,
          leading: const Icon(LimpidIcons.shield),
          onTap: () => context.go(AppRoutes.twoFactor),
        ),
        LimpidListTile(
          title: strings.apiKeysTitle,
          subtitle: strings.apiKeysSubtitle,
          leading: const Icon(LimpidIcons.code),
          onTap: () => context.go(AppRoutes.apiKeys),
        ),
        LimpidListTile(
          title: strings.webhooksTitle,
          subtitle: strings.webhooksSubtitle,
          leading: const Icon(LimpidIcons.globe),
          onTap: () => context.go(AppRoutes.webhooks),
        ),
      ],
    );
  }

  Widget _buildSync(
    BuildContext context,
    WidgetRef ref,
    SyncStatus status,
    int pending,
    SyncActionState syncAction,
  ) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final bool isAvailable =
        ref.watch(syncRepositoryProvider) is! UnavailableService;

    return SettingsSection(
      title: strings.settingsSectionSync,
      children: <Widget>[
        LimpidListTile(
          title: _statusLabel(strings, status, pending),
          subtitle: _statusDetail(context, strings, pending, syncAction),
          leading: Icon(
            _statusIcon(status),
            color: _statusColor(scope, status),
          ),
        ),
        LimpidListTile(
          title: strings.syncRetry,
          subtitle: isAvailable ? null : strings.demoModeMessage,
          leading: syncAction.isRunning
              ? const LimpidSpinner()
              : const Icon(LimpidIcons.sync),
          onTap: syncAction.isRunning || !isAvailable
              ? null
              : () => _synchronize(context, ref),
        ),
      ],
    );
  }

  Widget _buildDevices(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);

    return SettingsSection(
      title: strings.settingsSectionDevices,
      children: <Widget>[
        LimpidListTile(
          title: strings.dataEmptyTitle,
          subtitle: strings.demoModeMessage,
          leading: const Icon(LimpidIcons.info),
        ),
      ],
    );
  }

  Future<void> _pickGoal(BuildContext context, WidgetRef ref) async {
    final int current = ref.read(dailyWordGoalProvider);
    final int? choice = await showDailyWordGoalPicker(context, current);
    if (choice == null) {
      return;
    }
    ref.read(dailyWordGoalProvider.notifier).set(choice);
  }

  /// Pushes the pending operations to the server.
  ///
  /// The synchronisation goes to the server: it passes through the window of
  /// the second factor, and is repeated when the server refuses the proof.
  /// The operations are idempotent — the CRDT applies them twice without
  /// changing the manuscript.
  Future<void> _synchronize(BuildContext context, WidgetRef ref) async {
    final AppLocalizations strings = AppLocalizations.of(context);
    try {
      await runWithTwoFactor(
        context,
        ref,
        action: () => ref.read(syncActionProvider.notifier).synchronize(),
      );
    } on Exception {
      if (!context.mounted) {
        return;
      }
      LimpidSnackbar.show(
        context,
        message: strings.errorGeneric,
        variant: LimpidStatusVariant.danger,
      );
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et le
      // bouton semble ne rien faire. L'auteur voit un message, et la console
      // porte la cause.
      if (!context.mounted) {
        return;
      }
      LimpidSnackbar.show(
        context,
        message: strings.errorGeneric,
        variant: LimpidStatusVariant.danger,
      );
      debugPrint('La synchronisation a échoué : $error\n$stackTrace');
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final LocalDataChoice choice = await showLocalDataErasureChoice(context);
    if (choice == LocalDataChoice.cancel || !context.mounted) {
      return;
    }
    if (choice == LocalDataChoice.erase) {
      final LocalDataErasure outcome = await eraseLocalData(ref);
      if (!context.mounted) {
        return;
      }
      if (outcome != LocalDataErasure.erased) {
        showLocalDataErasureFailure(context, outcome);
      }
    }
    await closeSession(context, ref);
  }

  String _statusLabel(
    AppLocalizations strings,
    SyncStatus status,
    int pending,
  ) => switch (status) {
    SyncStatus.synced => strings.syncStatusSynced,
    SyncStatus.syncing => strings.syncStatusSyncing,
    SyncStatus.offline => strings.syncStatusOffline(pending),
    SyncStatus.conflict => strings.syncStatusConflict,
  };

  String? _statusDetail(
    BuildContext context,
    AppLocalizations strings,
    int pending,
    SyncActionState syncAction,
  ) {
    if (pending > 0) {
      return pending == 1
          ? strings.syncPending(pending)
          : strings.syncPendingPlural(pending);
    }
    final DateTime? lastSync = syncAction.lastSynchronizedAt;
    if (lastSync == null) {
      return null;
    }
    return strings.syncLastSync(_formatMoment(context, lastSync));
  }

  IconData _statusIcon(SyncStatus status) => switch (status) {
    SyncStatus.synced => LimpidIcons.success,
    SyncStatus.syncing => LimpidIcons.sync,
    SyncStatus.offline => LimpidIcons.offline,
    SyncStatus.conflict => LimpidIcons.warning,
  };

  Color _statusColor(LimpidThemeScope scope, SyncStatus status) =>
      switch (status) {
        SyncStatus.synced => scope.colors.success,
        SyncStatus.syncing => scope.colors.info,
        SyncStatus.offline => scope.colors.fgMuted,
        SyncStatus.conflict => scope.colors.warning,
      };

  String _formatMoment(BuildContext context, DateTime moment) {
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final String date = localizations.formatMediumDate(moment);
    final String time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(moment),
    );
    return '$date $time';
  }
}
