import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';

/// Les clés d'API du compte, lues sur le serveur.
///
/// La liste ne porte jamais de secret : le serveur ne le rend qu'à la
/// création et au renouvellement.
final apiKeysProvider = FutureProvider<List<ApiKey>>((Ref ref) async {
  return runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(webhookRepositoryProvider).apiKeys(),
  );
});

/// Les points de rappel du compte, lus sur le serveur.
final webhookEndpointsProvider = FutureProvider<List<WebhookEndpoint>>((
  Ref ref,
) async {
  return runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(webhookRepositoryProvider).endpoints(),
  );
});

/// Les livraisons du compte, lues sur le serveur.
///
/// Les livraisons sont les plus récentes d'abord : c'est l'ordre du
/// serveur.
final webhookDeliveriesProvider = FutureProvider<List<WebhookDelivery>>((
  Ref ref,
) async {
  return runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(webhookRepositoryProvider).deliveries(),
  );
});

/// Le catalogue des événements, lu sur le serveur.
///
/// La liste suit le serveur : elle n'est jamais figée dans l'application.
/// Le port la lit au moment où l'écran en a besoin.
final availableWebhookEventsProvider = FutureProvider<List<WebhookEvent>>((
  Ref ref,
) async {
  return runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(webhookRepositoryProvider).availableEvents(),
  );
});
