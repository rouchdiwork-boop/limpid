import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_app/src/features/webhooks/webhook_providers.dart';
import 'package:limpid_app/src/features/webhooks/webhook_widgets.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La demande de création ou de modification d'un point de réception.
final class EndpointDraft {
  /// Crée une demande.
  const EndpointDraft({required this.url, required this.events});

  /// L'adresse de réception.
  final String url;

  /// Les événements choisis.
  final Set<String> events;
}

/// Ouvre la fenêtre qui crée ou modifie un point de réception.
///
/// La fenêtre rend la demande de l'auteur, ou `null` quand il renonce.
/// Le catalogue des événements est lu sur le serveur : la fenêtre ne
/// propose que ce que le serveur publie.
Future<EndpointDraft?> showEndpointEdition(
  BuildContext context, {
  WebhookEndpoint? endpoint,
}) {
  return showDialog<EndpointDraft>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _EndpointDialog(endpoint: endpoint),
  );
}

/// La fenêtre qui crée ou modifie un point de réception.
final class _EndpointDialog extends ConsumerStatefulWidget {
  /// Crée la fenêtre.
  const _EndpointDialog({this.endpoint});

  /// Le point de réception modifié, `null` quand la fenêtre en crée un.
  final WebhookEndpoint? endpoint;

  @override
  ConsumerState<_EndpointDialog> createState() => _EndpointDialogState();
}

/// L'état de la fenêtre qui crée ou modifie un point de réception.
final class _EndpointDialogState extends ConsumerState<_EndpointDialog> {
  late final TextEditingController _url = TextEditingController(
    text: widget.endpoint?.url ?? '',
  );

  /// Les événements choisis.
  late Set<String> _events = Set<String>.of(
    widget.endpoint?.events ?? const <String>{},
  );

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// Rend la demande à l'écran.
  void _submit() {
    final String url = _url.text.trim();
    if (url.isEmpty || _events.isEmpty) return;
    Navigator.of(context).pop(EndpointDraft(url: url, events: _events));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope tokens = context.limpid;
    final AsyncValue<List<WebhookEvent>> catalogue = ref.watch(
      availableWebhookEventsProvider,
    );
    final List<WebhookEvent> events = catalogue.value ?? const <WebhookEvent>[];

    return LimpidDialog(
      title: widget.endpoint == null
          ? strings.webhooksCreate
          : strings.actionSave,
      icon: LimpidIcons.globe,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        LimpidButton(
          label: widget.endpoint == null
              ? strings.actionCreate
              : strings.actionSave,
          onPressed: _url.text.trim().isEmpty || _events.isEmpty
              ? null
              : _submit,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LimpidTextField(
            controller: _url,
            label: strings.webhooksUrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onChanged: (String _) => setState(() {}),
            onSubmitted: (String _) => _submit(),
          ),
          SizedBox(height: tokens.spacing.space16),
          if (catalogue.hasError)
            LimpidBanner(
              variant: catalogue.error is StudioPlanRequiredException
                  ? LimpidStatusVariant.warning
                  : LimpidStatusVariant.danger,
              title: catalogue.error is StudioPlanRequiredException
                  ? strings.webhooksStudioOnly
                  : strings.errorGeneric,
            )
          else
            WebhookEventPicker(
              events: events,
              selected: _events,
              onChanged: (Set<String> chosen) =>
                  setState(() => _events = chosen),
            ),
        ],
      ),
    );
  }
}

/// Demande à l'auteur de confirmer la suppression d'un point de réception.
///
/// La fenêtre rend `true` quand l'auteur confirme, `false` quand il
/// renonce.
Future<bool> showEndpointDeletion(BuildContext context, String url) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => LimpidDialog(
      title: strings.apiKeysDelete,
      icon: LimpidIcons.delete,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        LimpidButton(
          label: strings.apiKeysDelete,
          variant: LimpidButtonVariant.danger,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
      child: Text(
        url,
        style: LimpidTypography.monoStyle(
          color: dialogContext.limpid.colors.fgDefault,
        ),
      ),
    ),
  );
  return confirmed ?? false;
}
