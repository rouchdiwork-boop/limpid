import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';
import 'package:limpid_app/src/features/webhooks/webhook_providers.dart';
import 'package:limpid_app/src/features/webhooks/webhook_widgets.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'écran des livraisons des webhooks.
///
/// L'écran montre les livraisons du compte, leur statut, et permet de
/// rejouer une livraison. Le rejeu renvoie la même charge : le destinataire
/// peut écarter le doublon.
class WebhookDeliveriesScreen extends ConsumerStatefulWidget {
  /// Crée l'écran.
  const WebhookDeliveriesScreen({super.key});

  @override
  ConsumerState<WebhookDeliveriesScreen> createState() =>
      _WebhookDeliveriesScreenState();
}

/// L'état de l'écran des livraisons.
final class _WebhookDeliveriesScreenState
    extends ConsumerState<WebhookDeliveriesScreen> {
  /// L'identifiant de la livraison en cours de rejeu, `null` quand aucune
  /// livraison ne l'est.
  String? _replaying;

  /// Rejoue la livraison [delivery].
  ///
  /// Le rejeu va au serveur : il passe par la fenêtre du second facteur. Le
  /// rejeu refusé n'a jamais atteint le destinataire : la répétition n'en
  /// livre donc qu'un.
  Future<void> _replay(WebhookDelivery delivery) async {
    if (_replaying != null) return;
    setState(() => _replaying = delivery.id);
    try {
      await runWithTwoFactor(
        context,
        ref,
        action: () =>
            ref.read(webhookRepositoryProvider).replayDelivery(delivery.id),
      );
      if (!mounted) return;
      setState(() => _replaying = null);
      ref.invalidate(webhookDeliveriesProvider);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _replaying = null);
      _reportFailure(error);
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et le
      // bouton semble ne rien faire. L'auteur voit un message, et la console
      // porte la cause.
      if (!mounted) return;
      setState(() => _replaying = null);
      _reportFailure(error);
      debugPrint('Le rejeu de la livraison a échoué : $error\n$stackTrace');
    }
  }

  /// Dit à l'auteur que le rejeu a échoué.
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
    final AsyncValue<List<WebhookDelivery>> deliveries = ref.watch(
      webhookDeliveriesProvider,
    );
    final AsyncValue<List<WebhookEvent>> catalogue = ref.watch(
      availableWebhookEventsProvider,
    );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(scope.spacing.space24),
          children: <Widget>[
            _header(context, strings),
            SizedBox(height: scope.spacing.space24),
            if (!isAvailable)
              LimpidBanner(
                variant: LimpidStatusVariant.info,
                title: strings.demoModeTitle,
                message: strings.demoModeMessage,
              )
            else
              _deliveries(
                context,
                strings,
                deliveries,
                catalogue.value ?? const <WebhookEvent>[],
              ),
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
          strings.webhooksDeliveries,
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

  /// La liste des livraisons.
  Widget _deliveries(
    BuildContext context,
    AppLocalizations strings,
    AsyncValue<List<WebhookDelivery>> deliveries,
    List<WebhookEvent> catalogue,
  ) {
    return deliveries.when(
      loading: () => const Center(child: LimpidSpinner()),
      error: (Object error, StackTrace stack) =>
          _failure(context, strings, error),
      data: (List<WebhookDelivery> list) =>
          _list(context, strings, list, catalogue),
    );
  }

  /// La liste des livraisons, une fois lue.
  Widget _list(
    BuildContext context,
    AppLocalizations strings,
    List<WebhookDelivery> deliveries,
    List<WebhookEvent> catalogue,
  ) {
    final LimpidThemeScope scope = context.limpid;
    if (deliveries.isEmpty) {
      return LimpidEmptyState(
        title: strings.dataEmptyTitle,
        icon: LimpidIcons.list,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final WebhookDelivery delivery in deliveries) ...<Widget>[
          _deliveryCard(context, strings, delivery, catalogue),
          SizedBox(height: scope.spacing.space12),
        ],
      ],
    );
  }

  /// La carte d'une livraison.
  Widget _deliveryCard(
    BuildContext context,
    AppLocalizations strings,
    WebhookDelivery delivery,
    List<WebhookEvent> catalogue,
  ) {
    final LimpidThemeScope tokens = context.limpid;
    final String? failure = delivery.errorMessage;

    return LimpidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(LimpidIcons.list),
              SizedBox(width: tokens.spacing.space12),
              Expanded(
                child: Text(
                  _labelOf(catalogue, delivery.event),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.colors.fgDefault,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.space8),
              LimpidBadge(
                label: _statusOf(strings, delivery.status),
                variant: _variantOf(delivery.status),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.space12),
          _deliveryDetails(context, delivery),
          if (failure != null) ...<Widget>[
            SizedBox(height: tokens.spacing.space8),
            Text(
              failure,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.colors.fgMuted),
            ),
          ],
          SizedBox(height: tokens.spacing.space12),
          LimpidButton(
            label: strings.webhooksReplay,
            variant: LimpidButtonVariant.ghost,
            expand: true,
            loading: _replaying == delivery.id,
            onPressed: _replaying == null ? () => _replay(delivery) : null,
          ),
        ],
      ),
    );
  }

  /// Le détail d'une livraison : son point de réception et sa date.
  Widget _deliveryDetails(BuildContext context, WebhookDelivery delivery) {
    final LimpidThemeScope scope = context.limpid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          delivery.endpointId,
          style: LimpidTypography.monoStyle(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space4),
        Row(
          children: <Widget>[
            Icon(LimpidIcons.clock, size: 14, color: scope.colors.fgMuted),
            SizedBox(width: scope.spacing.space4),
            Text(
              formatWebhookDate(context, delivery.createdAt),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
            ),
          ],
        ),
      ],
    );
  }

  /// Le libellé d'un événement, tel que le serveur le publie.
  static String _labelOf(List<WebhookEvent> catalogue, String key) {
    for (final WebhookEvent event in catalogue) {
      if (event.key == key) return event.label;
    }
    return key;
  }

  /// Le libellé d'un statut de livraison.
  static String _statusOf(
    AppLocalizations strings,
    WebhookDeliveryStatus status,
  ) {
    return switch (status) {
      WebhookDeliveryStatus.pending => strings.webhooksDeliveryPending,
      WebhookDeliveryStatus.succeeded => strings.webhooksDeliveryDelivered,
      WebhookDeliveryStatus.failed => strings.webhooksDeliveryFailed,
    };
  }

  /// La couleur d'un statut de livraison.
  static LimpidStatusVariant _variantOf(WebhookDeliveryStatus status) {
    return switch (status) {
      WebhookDeliveryStatus.pending => LimpidStatusVariant.info,
      WebhookDeliveryStatus.succeeded => LimpidStatusVariant.success,
      WebhookDeliveryStatus.failed => LimpidStatusVariant.danger,
    };
  }

  /// L'état d'échec de la lecture des livraisons.
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
        onPressed: () => ref.invalidate(webhookDeliveriesProvider),
      ),
    );
  }
}
