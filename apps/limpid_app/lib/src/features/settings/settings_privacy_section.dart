import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/ai_consent_repository.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'settings_sections.dart';

/// L'état du consentement, lu sur le serveur.
///
/// L'état est relu après chaque décision : l'accord de l'auteur est
/// **le sien**, et l'écran montre ce que le serveur a enregistré.
final aiConsentProvider = FutureProvider<AiConsentState>((Ref ref) {
  return ref.watch(aiConsentRepositoryProvider).state();
});

/// La section « Confidentialité » de l'écran des réglages.
///
/// D-08 : le texte de l'auteur ne part chez un fournisseur qu'après un
/// accord explicite. L'accord est ici, il se retire ici, et l'écran dit
/// ce que l'accord veut dire — y compris où part le texte.
class SettingsPrivacySection extends ConsumerWidget {
  /// Crée la section.
  const SettingsPrivacySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final AsyncValue<AiConsentState> consent = ref.watch(aiConsentProvider);

    return SettingsSection(
      title: strings.settingsSectionPrivacy,
      children: <Widget>[
        consent.when(
          loading: () => const Center(child: LimpidSpinner()),
          error: (Object error, StackTrace stack) => LimpidBanner(
            variant: LimpidStatusVariant.danger,
            title: strings.settingsAiConsentFailed,
          ),
          data: (AiConsentState state) => _consent(context, ref, state),
        ),
      ],
    );
  }

  /// L'accord lui-même : l'interrupteur, et ce qu'il dit.
  Widget _consent(BuildContext context, WidgetRef ref, AiConsentState state) {
    final AppLocalizations strings = AppLocalizations.of(context);

    if (!state.requiresConsent) {
      // Le fournisseur tourne sur la machine de l'auteur : rien ne part,
      // et aucun accord n'est demandé.
      return LimpidBanner(
        variant: LimpidStatusVariant.info,
        title: strings.settingsAiConsentLocal,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // L'interrupteur est une tuile : il peint ses effets sur le
        // `Material` le plus proche. La section est une carte — une
        // `DecoratedBox` — l'interrupteur a besoin de son propre `Material`,
        // sans quoi ses effets seraient invisibles.
        Material(
          type: MaterialType.transparency,
          child: LimpidSwitch(
            value: state.isGranted,
            label: strings.settingsAiConsentTitle,
            description: strings.settingsAiConsentSubtitle,
            onChanged: (bool granted) => _decide(context, ref, granted),
          ),
        ),
        SizedBox(height: context.limpid.spacing.space12),
        Text(
          state.isGranted
              ? strings.settingsAiConsentEnabled
              : strings.settingsAiConsentDisabled,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (state.grantedAt != null)
          Text(
            strings.settingsAiConsentGrantedAt(_dateOf(state.grantedAt!)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (state.revokedAt != null)
          Text(
            strings.settingsAiConsentRevokedAt(_dateOf(state.revokedAt!)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        SizedBox(height: context.limpid.spacing.space12),
        Text(
          strings.settingsAiConsentRisk,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Enregistre la décision de l'auteur.
  ///
  /// L'échec est dit : un accord que le serveur n'a pas enregistré n'est
  /// pas un accord donné.
  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    bool granted,
  ) async {
    final AppLocalizations strings = AppLocalizations.of(context);
    final AiConsentRepository repository = ref.read(
      aiConsentRepositoryProvider,
    );
    try {
      if (granted) {
        await repository.grant();
      } else {
        await repository.revoke();
      }
    } on Object {
      if (!context.mounted) return;
      LimpidSnackbar.show(
        context,
        message: strings.settingsAiConsentFailed,
        variant: LimpidStatusVariant.danger,
      );
      return;
    }
    ref.invalidate(aiConsentProvider);
  }

  /// La date de la décision, en clair.
  String _dateOf(DateTime moment) {
    final String month = moment.month.toString().padLeft(2, '0');
    final String day = moment.day.toString().padLeft(2, '0');
    return '${moment.year}-$month-$day';
  }
}
