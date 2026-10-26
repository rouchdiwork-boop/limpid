import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_app/src/features/webhooks/webhooks_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  group("l'écran des points de réception", () {
    testWidgets('montre les points de réception du compte', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        webhooksHarness(
          repository: FakeWebhookRepository(
            endpoints: <WebhookEndpoint>[fakeEndpoint],
            events: fakeEvents,
          ),
          home: const WebhooksScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhooksScreen),
      );

      expect(find.text(strings.webhooksTitle), findsOneWidget);
      expect(find.text('https://exemple.test/limpid'), findsOneWidget);
      expect(find.text(strings.webhooksEmpty), findsNothing);
    });

    testWidgets('dit que le compte n’a pas de point de réception', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        webhooksHarness(
          repository: FakeWebhookRepository(events: fakeEvents),
          home: const WebhooksScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhooksScreen),
      );

      expect(find.text(strings.webhooksEmpty), findsOneWidget);
    });

    testWidgets('crée un point de réception et montre son secret une fois', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1400));
      final FakeWebhookRepository repository = FakeWebhookRepository(
        events: fakeEvents,
      );
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const WebhooksScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhooksScreen),
      );

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.webhooksCreate),
      );
      await tester.pumpAndSettle();

      // Les événements viennent du serveur : la fenêtre les propose.
      expect(find.text('Projet publié'), findsOneWidget);

      await tester.enterText(
        find.byType(LimpidTextField),
        'https://exemple.test/limpid',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Projet publié'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(LimpidDialog),
          matching: find.widgetWithText(LimpidButton, strings.actionCreate),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.createdEndpoints, hasLength(1));
      expect(
        repository.createdEndpoints.first.$1,
        'https://exemple.test/limpid',
      );
      expect(repository.createdEndpoints.first.$2, <String>{
        'project.published',
      });

      // Le secret de signature est montré, une seule fois.
      expect(find.text(strings.webhooksSecret), findsOneWidget);
      expect(find.text(fakeEndpointSecret), findsOneWidget);
    });

    testWidgets('ne montre plus le secret quand l’écran est rouvert', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1400));
      final FakeWebhookRepository repository = FakeWebhookRepository(
        events: fakeEvents,
      );
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const WebhooksScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhooksScreen),
      );

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.webhooksCreate),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(LimpidTextField),
        'https://exemple.test/limpid',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Projet publié'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(LimpidDialog),
          matching: find.widgetWithText(LimpidButton, strings.actionCreate),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(fakeEndpointSecret), findsOneWidget);

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.actionContinue),
      );
      await tester.pumpAndSettle();
      expect(find.text(fakeEndpointSecret), findsNothing);

      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const SizedBox()),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const WebhooksScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text(fakeEndpointSecret), findsNothing);
    });

    testWidgets('renouvelle le secret de signature', (tester) async {
      useSurface(tester, const Size(900, 1400));
      final FakeWebhookRepository repository = FakeWebhookRepository(
        endpoints: <WebhookEndpoint>[fakeEndpoint],
        events: fakeEvents,
      );
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const WebhooksScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhooksScreen),
      );

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.webhooksRotateSecret),
      );
      await tester.pumpAndSettle();

      expect(repository.rotatedEndpoints, <String>['endpoint-1']);
      expect(find.text(strings.webhooksSecret), findsOneWidget);
      expect(find.text(fakeEndpointSecret), findsOneWidget);
    });

    testWidgets('modifie un point de réception', (tester) async {
      useSurface(tester, const Size(900, 1400));
      final FakeWebhookRepository repository = FakeWebhookRepository(
        endpoints: <WebhookEndpoint>[fakeEndpoint],
        events: fakeEvents,
      );
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const WebhooksScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhooksScreen),
      );

      await tester.tap(find.widgetWithText(LimpidButton, strings.actionSave));
      await tester.pumpAndSettle();

      expect(find.byType(LimpidDialog), findsOneWidget);
      await tester.enterText(
        find.byType(LimpidTextField),
        'https://autre.test/limpid',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(LimpidDialog),
          matching: find.widgetWithText(LimpidButton, strings.actionSave),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.updatedEndpoints, hasLength(1));
      expect(repository.updatedEndpoints.first.$1, 'endpoint-1');
      expect(repository.updatedEndpoints.first.$2, 'https://autre.test/limpid');
    });

    testWidgets('supprime un point de réception après confirmation', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1400));
      final FakeWebhookRepository repository = FakeWebhookRepository(
        endpoints: <WebhookEndpoint>[fakeEndpoint],
        events: fakeEvents,
      );
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const WebhooksScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhooksScreen),
      );

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.apiKeysDelete),
      );
      await tester.pumpAndSettle();

      expect(repository.deletedEndpoints, isEmpty);

      await tester.tap(
        find.descendant(
          of: find.byType(LimpidDialog),
          matching: find.widgetWithText(LimpidButton, strings.apiKeysDelete),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.deletedEndpoints, <String>['endpoint-1']);
      expect(find.text('https://exemple.test/limpid'), findsNothing);
    });

    testWidgets('ne propose rien quand le catalogue des événements se tait', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1400));
      final FakeWebhookRepository repository = FakeWebhookRepository(
        endpoints: <WebhookEndpoint>[fakeEndpoint],
      )..eventsError = const StudioPlanRequiredException();
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const WebhooksScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhooksScreen),
      );

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.webhooksCreate),
      );
      await tester.pumpAndSettle();

      // Le catalogue ne se lit pas : l'écran le dit et ne propose aucun
      // événement, plutôt que d'en inventer.
      expect(find.text(strings.webhooksStudioOnly), findsWidgets);
      expect(find.text('Projet publié'), findsNothing);

      final Finder create = find.descendant(
        of: find.byType(LimpidDialog),
        matching: find.widgetWithText(LimpidButton, strings.actionCreate),
      );
      expect(tester.widget<LimpidButton>(create).onPressed, isNull);
    });

    testWidgets('dit que la formule Studio est nécessaire', (tester) async {
      useSurface(tester, const Size(900, 900));
      final FakeWebhookRepository repository = FakeWebhookRepository()
        ..error = const StudioPlanRequiredException();
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const WebhooksScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhooksScreen),
      );

      // Le refus se lit comme un refus : jamais une liste vide.
      expect(find.text(strings.webhooksStudioOnly), findsOneWidget);
      expect(find.text(strings.webhooksEmpty), findsNothing);
    });

    testWidgets('dit que le service n’est pas configuré', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        webhooksHarness(
          repository: const UnavailableWebhookRepository(),
          home: const WebhooksScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(WebhooksScreen),
      );

      expect(find.text(strings.demoModeTitle), findsOneWidget);
      expect(
        find.widgetWithText(LimpidButton, strings.webhooksCreate),
        findsNothing,
      );
    });
  });
}
