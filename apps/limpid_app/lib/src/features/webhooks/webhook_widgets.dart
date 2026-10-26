import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Le panneau qui montre un secret, une seule fois.
///
/// Le secret d'une clé d'API et le secret de signature d'un point de
/// rappel ne sont rendus qu'une fois par le serveur. Le panneau les montre,
/// il ne les garde pas : quand l'auteur le referme, le secret est perdu.
class WebhookSecretPanel extends StatelessWidget {
  /// Crée le panneau.
  const WebhookSecretPanel({
    super.key,
    this.subject,
    required this.label,
    required this.secret,
    required this.warning,
    required this.onDismiss,
  });

  /// Le nom de ce qui porte le secret, quand l'écran le sait.
  ///
  /// L'auteur voit ainsi à quoi le secret appartient : une clé parmi
  /// plusieurs, un point de réception parmi plusieurs.
  final String? subject;

  /// Le nom du secret, celui que l'auteur cherche.
  final String label;

  /// Le secret, en clair.
  final String secret;

  /// L'avertissement qui accompagne le secret.
  final String warning;

  /// Appelé quand l'auteur a recopié le secret et referme le panneau.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LimpidBanner(variant: LimpidStatusVariant.warning, title: warning),
        SizedBox(height: scope.spacing.space8),
        LimpidCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (subject != null) ...<Widget>[
                Text(
                  subject!,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scope.colors.fgDefault,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: scope.spacing.space8),
              ],
              Text(
                label,
                style: LimpidTypography.labelStyle(color: scope.colors.fgMuted),
              ),
              SizedBox(height: scope.spacing.space8),
              SelectableText(
                secret,
                style: LimpidTypography.monoStyle(
                  color: scope.colors.fgDefault,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: scope.spacing.space8),
        LimpidButton(
          label: strings.actionContinue,
          expand: true,
          onPressed: onDismiss,
        ),
      ],
    );
  }
}

/// La liste des événements qu'un point de rappel peut choisir.
///
/// Les événements viennent du serveur : l'application ne les fige pas. Le
/// panneau les présente comme des puces, et l'auteur en choisit au moins un.
class WebhookEventPicker extends StatelessWidget {
  /// Crée le panneau.
  const WebhookEventPicker({
    super.key,
    required this.events,
    required this.selected,
    required this.onChanged,
  });

  /// Les événements que le serveur publie.
  final List<WebhookEvent> events;

  /// Les événements choisis.
  final Set<String> selected;

  /// Appelé quand l'auteur change son choix.
  final ValueChanged<Set<String>> onChanged;

  /// Ajoute l'événement [event] au choix, ou l'en retire.
  void _toggle(WebhookEvent event) {
    final Set<String> next = Set<String>.of(selected);
    if (!next.remove(event.key)) next.add(event.key);
    onChanged(Set<String>.unmodifiable(next));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          strings.webhooksEvents,
          style: LimpidTypography.labelStyle(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space8),
        if (events.isEmpty)
          Text(
            strings.dataEmptyTitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
          )
        else
          Wrap(
            spacing: scope.spacing.space8,
            runSpacing: scope.spacing.space8,
            children: <Widget>[
              for (final WebhookEvent event in events)
                LimpidChip(
                  label: event.label,
                  isSelected: selected.contains(event.key),
                  onTap: () => _toggle(event),
                ),
            ],
          ),
      ],
    );
  }
}

/// La date que l'auteur lit.
String formatWebhookDate(BuildContext context, DateTime moment) {
  return MaterialLocalizations.of(context).formatMediumDate(moment.toLocal());
}
