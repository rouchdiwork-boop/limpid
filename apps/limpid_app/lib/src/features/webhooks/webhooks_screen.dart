import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';
import 'package:limpid_app/src/features/webhooks/webhook_dialogs.dart';
import 'package:limpid_app/src/features/webhooks/webhook_providers.dart';
import 'package:limpid_app/src/features/webhooks/webhook_widgets.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'écran des points de réception des webhooks.
///
/// L'écran montre les points de rappel du compte, en crée, en modifie, en
/// renouvelle le secret de signature et en supprime. Le secret de signature
/// est **rendu une seule fois** : l'écran le montre, puis il ne ment jamais
/// sur sa présence.
class WebhooksScreen extends ConsumerStatefulWidget {
  /// Crée l'écran.
  const WebhooksScreen({super.key});

  @override
  ConsumerState<WebhooksScreen> createState() => _WebhooksScreenState();
}

/// L'état de l'écran des points de réception.
final class _WebhooksScreenState extends ConsumerState<WebhooksScreen> {
  /// Le secret montré à l'auteur, `null` quand l'écran n'en montre aucun.
  String? _secret;

  /// L'adresse du point de réception dont le secret est montré.
  String? _secretUrl;

  /// Une opération est-elle en cours ?
  bool _isBusy = false;

  /// Ouvre la fenêtre de création d'un point de réception.
  ///
  /// La création va au serveur : elle passe par la fenêtre du second
  /// facteur, et le point n'est créé qu'une fois.
  Future<void> _create() async {
    final EndpointDraft? draft = await showEndpointEdition(context);
    if (draft == null || !mounted) return;

    setState(() => _isBusy = true);
    try {
      final WebhookEndpointSecret created = await runWithTwoFactor(
        context,
        ref,
        action: () => ref
            .read(webhookRepositoryProvider)
            .createEndpoint(url: draft.url, events: draft.events),
      );
      if (!mounted) return;
      setState(() {
        _secret = created.secret;
        _secretUrl = created.endpoint.url;
        _isBusy = false;
      });
      ref.invalidate(webhookEndpointsProvider);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et le
      // bouton semble ne rien faire. L'auteur voit un message, et la console
      // porte la cause.
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
      debugPrint(
        'L\'action sur le point de réception a échoué : $error\n$stackTrace',
      );
    }
  }

  /// Modifie le point de réception [endpoint].
  ///
  /// La modification va au serveur : elle passe par la fenêtre du second
  /// facteur. La modification refusée n'a jamais été appliquée : la
  /// répétition n'en applique qu'une.
  Future<void> _update(WebhookEndpoint endpoint) async {
    final EndpointDraft? draft = await showEndpointEdition(
      context,
      endpoint: endpoint,
    );
    if (draft == null || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await runWithTwoFactor(
        context,
        ref,
        action: () => ref
            .read(webhookRepositoryProvider)
            .updateEndpoint(endpoint.id, url: draft.url, events: draft.events),
      );
      if (!mounted) return;
      setState(() => _isBusy = false);
      ref.invalidate(webhookEndpointsProvider);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et le
      // bouton semble ne rien faire. L'auteur voit un message, et la console
      // porte la cause.
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
      debugPrint(
        'L\'action sur le point de réception a échoué : $error\n$stackTrace',
      );
    }
  }

  /// Renouvelle le secret de signature du point de réception [endpoint].
  ///
  /// Le renouvellement va au serveur : il passe par la fenêtre du second
  /// facteur. Le secret refusé n'a jamais été renouvelé : la répétition
  /// n'en rend donc qu'un.
  Future<void> _rotateSecret(WebhookEndpoint endpoint) async {
    setState(() => _isBusy = true);
    try {
      final WebhookEndpointSecret rotated = await runWithTwoFactor(
        context,
        ref,
        action: () => ref
            .read(webhookRepositoryProvider)
            .rotateEndpointSecret(endpoint.id),
      );
      if (!mounted) return;
      setState(() {
        _secret = rotated.secret;
        _secretUrl = rotated.endpoint.url;
        _isBusy = false;
      });
      ref.invalidate(webhookEndpointsProvider);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et le
      // bouton semble ne rien faire. L'auteur voit un message, et la console
      // porte la cause.
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
      debugPrint(
        'L\'action sur le point de réception a échoué : $error\n$stackTrace',
      );
    }
  }

  /// Supprime le point de réception [endpoint], après confirmation.
  ///
  /// La suppression va au serveur : elle passe par la fenêtre du second
  /// facteur.
  Future<void> _delete(WebhookEndpoint endpoint) async {
    final bool confirmed = await showEndpointDeletion(context, endpoint.url);
    if (!confirmed || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await runWithTwoFactor(
        context,
        ref,
        action: () =>
            ref.read(webhookRepositoryProvider).deleteEndpoint(endpoint.id),
      );
      if (!mounted) return;
      setState(() => _isBusy = false);
      ref.invalidate(webhookEndpointsProvider);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et le
      // bouton semble ne rien faire. L'auteur voit un message, et la console
      // porte la cause.
      if (!mounted) return;
      setState(() => _isBusy = false);
      _reportFailure(error);
      debugPrint(
        'L\'action sur le point de réception a échoué : $error\n$stackTrace',
      );
    }
  }

  /// Referme le panneau du secret : le secret est perdu.
  void _dismissSecret() {
    setState(() {
      _secret = null;
      _secretUrl = null;
    });
  }

  /// Dit à l'auteur que l'opération a échoué.
  void _reportFailure(Object error) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final bool isForbidden = error is StudioPlanRequiredException;
    LimpidSnackbar.show(
      context,
      message: isForbidden ? strings.webhooksStudioOnly : strings.errorGeneric,
      variant: isForbidden
          ? LimpidStatusVariant.warning
          : LimpidStatusVariant.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final bool isAvailable =
        ref.watch(webhookRepositoryProvider) is! UnavailableService;
    final AsyncValue<List<WebhookEndpoint>> endpoints = ref.watch(
      webhookEndpointsProvider,
    );
    final AsyncValue<List<WebhookEvent>> catalogue = ref.watch(
      availableWebhookEventsProvider,
    );
    final String? secret = _secret;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(scope.spacing.space24),
          children: <Widget>[
            _header(context, strings),
            SizedBox(height: scope.spacing.space24),
            if (secret != null) ...<Widget>[
              WebhookSecretPanel(
                subject: _secretUrl,
                label: strings.webhooksSecret,
                secret: secret,
                warning: strings.apiKeysSecretWarning,
                onDismiss: _dismissSecret,
              ),
              SizedBox(height: scope.spacing.space24),
            ],
            if (!isAvailable)
              LimpidBanner(
                variant: LimpidStatusVariant.info,
                title: strings.demoModeTitle,
                message: strings.demoModeMessage,
              )
            else ...<Widget>[
              LimpidButton(
                label: strings.webhooksCreate,
                icon: LimpidIcons.add,
                expand: true,
                loading: _isBusy,
                onPressed: _create,
              ),
              SizedBox(height: scope.spacing.space16),
              _endpoints(context, strings, endpoints, catalogue),
            ],
          ],
        ),
      ),
    );
  }

  /// Le titre et la phrase d'introduction de la page.
  Widget _header(BuildContext context, AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        Text(
          strings.webhooksTitle,
          textAlign: TextAlign.center,
          style: textTheme.headlineMedium?.copyWith(
            color: scope.colors.fgDefault,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: scope.spacing.space8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            strings.webhooksSubtitle,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
          ),
        ),
      ],
    );
  }

  /// La liste des points de réception.
  Widget _endpoints(
    BuildContext context,
    AppLocalizations strings,
    AsyncValue<List<WebhookEndpoint>> endpoints,
    AsyncValue<List<WebhookEvent>> catalogue,
  ) {
    return endpoints.when(
      loading: () => const Center(child: LimpidSpinner()),
      error: (Object error, StackTrace stack) =>
          _failure(context, strings, error),
      data: (List<WebhookEndpoint> list) => _list(
        context,
        strings,
        list,
        catalogue.value ?? const <WebhookEvent>[],
      ),
    );
  }

  /// La liste des points de réception, une fois lue.
  Widget _list(
    BuildContext context,
    AppLocalizations strings,
    List<WebhookEndpoint> endpoints,
    List<WebhookEvent> catalogue,
  ) {
    final LimpidThemeScope scope = context.limpid;
    if (endpoints.isEmpty) {
      return LimpidEmptyState(
        title: strings.webhooksEmpty,
        icon: LimpidIcons.globe,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final WebhookEndpoint endpoint in endpoints) ...<Widget>[
          _endpointCard(context, strings, endpoint, catalogue),
          SizedBox(height: scope.spacing.space12),
        ],
      ],
    );
  }

  /// La carte d'un point de réception.
  Widget _endpointCard(
    BuildContext context,
    AppLocalizations strings,
    WebhookEndpoint endpoint,
    List<WebhookEvent> catalogue,
  ) {
    final LimpidThemeScope tokens = context.limpid;

    return LimpidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(LimpidIcons.globe),
              SizedBox(width: tokens.spacing.space12),
              Expanded(
                child: Text(
                  endpoint.url,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.colors.fgDefault,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.space8),
              LimpidBadge(
                label: endpoint.isActive
                    ? strings.twoFactorStateOn
                    : strings.twoFactorStateOff,
                variant: endpoint.isActive
                    ? LimpidStatusVariant.success
                    : LimpidStatusVariant.neutral,
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.space12),
          _endpointDetails(context, endpoint, catalogue),
          SizedBox(height: tokens.spacing.space12),
          Row(
            children: <Widget>[
              Expanded(
                child: LimpidButton(
                  label: strings.actionSave,
                  variant: LimpidButtonVariant.ghost,
                  onPressed: _isBusy ? null : () => _update(endpoint),
                ),
              ),
              SizedBox(width: tokens.spacing.space8),
              Expanded(
                child: LimpidButton(
                  label: strings.webhooksRotateSecret,
                  variant: LimpidButtonVariant.ghost,
                  onPressed: _isBusy ? null : () => _rotateSecret(endpoint),
                ),
              ),
              SizedBox(width: tokens.spacing.space8),
              Expanded(
                child: LimpidButton(
                  label: strings.apiKeysDelete,
                  variant: LimpidButtonVariant.danger,
                  onPressed: _isBusy ? null : () => _delete(endpoint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Le détail d'un point de réception : ses événements.
  Widget _endpointDetails(
    BuildContext context,
    WebhookEndpoint endpoint,
    List<WebhookEvent> catalogue,
  ) {
    final LimpidThemeScope scope = context.limpid;
    final List<String> labels = endpoint.events
        .map((String key) => _labelOf(catalogue, key))
        .toList(growable: false);

    return Wrap(
      spacing: scope.spacing.space8,
      runSpacing: scope.spacing.space4,
      children: <Widget>[
        for (final String label in labels)
          LimpidBadge(label: label, variant: LimpidStatusVariant.neutral),
      ],
    );
  }

  /// Le libellé d'un événement, tel que le serveur le publie.
  ///
  /// Un événement que le catalogue ne connaît pas garde son nom technique :
  /// l'écran montre le nom du serveur plutôt qu'un libellé inventé.
  static String _labelOf(List<WebhookEvent> catalogue, String key) {
    for (final WebhookEvent event in catalogue) {
      if (event.key == key) return event.label;
    }
    return key;
  }

  /// L'état d'échec de la lecture des points de réception.
  Widget _failure(
    BuildContext context,
    AppLocalizations strings,
    Object error,
  ) {
    if (error is StudioPlanRequiredException) {
      return LimpidBanner(
        variant: LimpidStatusVariant.warning,
        title: strings.webhooksStudioOnly,
      );
    }
    if (error is ServiceUnavailableException) {
      return LimpidBanner(
        variant: LimpidStatusVariant.info,
        title: strings.demoModeTitle,
        message: strings.demoModeMessage,
      );
    }
    return LimpidEmptyState(
      title: strings.errorGeneric,
      icon: LimpidIcons.error,
      action: LimpidButton(
        label: strings.actionRetry,
        onPressed: () => ref.invalidate(webhookEndpointsProvider),
      ),
    );
  }
}
