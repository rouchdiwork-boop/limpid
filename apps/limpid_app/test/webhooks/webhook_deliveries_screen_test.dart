import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_app/src/features/webhooks/webhook_deliveries_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  group("l'écran des livraisons", () {
    testWidgets('montre les livraisons et leur statut', (tester) async {
      useSurface(tester, const Size(900, 1200));
      await tester.pumpWidget(
        webhooksHarness(
          repository: FakeWebhookRepository(
            deliveries: <WebhookDelivery>[fakeDelivery, fakeFailedDelivery],
            events: fakeEvents,
          ),
          home: const WebhookDeliveriesScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhookDeliveriesScreen),
      );

      expect(find.text(strings.webhooksDeliveries), findsOneWidget);
      expect(find.text(strings.webhooksDeliveryDelivered), findsOneWidget);
      expect(find.text(strings.webhooksDeliveryFailed), findsOneWidget);

      // Le libellé de l'événement vient du serveur.
      expect(find.text('Projet publié'), findsOneWidget);
      expect(find.text('Export terminé'), findsOneWidget);
    });

    testWidgets('montre le motif d’un échec', (tester) async {
      useSurface(tester, const Size(900, 1200));
      await tester.pumpWidget(
        webhooksHarness(
          repository: FakeWebhookRepository(
            deliveries: <WebhookDelivery>[fakeFailedDelivery],
            events: fakeEvents,
          ),
          home: const WebhookDeliveriesScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Le point de rappel a répondu 500.'), findsOneWidget);
    });

    testWidgets('rejoue une livraison', (tester) async {
      useSurface(tester, const Size(900, 1200));
      final FakeWebhookRepository repository = FakeWebhookRepository(
        deliveries: <WebhookDelivery>[fakeDelivery],
        events: fakeEvents,
      );
      await tester.pumpWidget(
        webhooksHarness(
          repository: repository,
          home: const WebhookDeliveriesScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhookDeliveriesScreen),
      );

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.webhooksReplay),
      );
      await tester.pumpAndSettle();

      expect(repository.replayed, <String>['delivery-1']);
    });

    testWidgets('dit que le compte n’a pas de livraison', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        webhooksHarness(
          repository: FakeWebhookRepository(events: fakeEvents),
          home: const WebhookDeliveriesScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhookDeliveriesScreen),
      );

      expect(find.text(strings.dataEmptyTitle), findsOneWidget);
    });

    testWidgets('dit que la formule Studio est nécessaire', (tester) async {
      useSurface(tester, const Size(900, 900));
      final FakeWebhookRepository repository = FakeWebhookRepository()
        ..error = const StudioPlanRequiredException();
      await tester.pumpWidget(
        webhooksHarness(
          repository: repository,
          home: const WebhookDeliveriesScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhookDeliveriesScreen),
      );

      // Le refus se lit comme un refus : jamais une liste vide.
      expect(find.text(strings.webhooksStudioOnly), findsOneWidget);
      expect(find.text(strings.dataEmptyTitle), findsNothing);
    });

    testWidgets('dit que le service n’est pas configuré', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        webhooksHarness(
          repository: const UnavailableWebhookRepository(),
          home: const WebhookDeliveriesScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhookDeliveriesScreen),
      );

      expect(find.text(strings.demoModeTitle), findsOneWidget);
    });
  });
}
