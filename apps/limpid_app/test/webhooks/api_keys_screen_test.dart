import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_app/src/features/webhooks/api_keys_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  group("l'écran des clés d'API", () {
    testWidgets('montre les clés du compte', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        webhooksHarness(
          repository: FakeWebhookRepository(keys: <ApiKey>[fakeApiKey]),
          home: const ApiKeysScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(ApiKeysScreen),
      );

      expect(find.text(strings.apiKeysTitle), findsOneWidget);
      expect(find.text('Intégration'), findsOneWidget);
      expect(find.text(strings.apiKeysEmpty), findsNothing);
    });

    testWidgets('dit que le compte n’a pas de clé', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        webhooksHarness(
          repository: FakeWebhookRepository(),
          home: const ApiKeysScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(ApiKeysScreen),
      );

      expect(find.text(strings.apiKeysEmpty), findsOneWidget);
    });

    testWidgets('crée une clé et montre le secret une fois', (tester) async {
      useSurface(tester, const Size(900, 1200));
      final FakeWebhookRepository repository = FakeWebhookRepository();
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const ApiKeysScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(ApiKeysScreen),
      );

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.apiKeysCreate),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(LimpidTextField), 'Mon script');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(LimpidDialog),
          matching: find.widgetWithText(LimpidButton, strings.apiKeysCreate),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.createdKeys, hasLength(1));
      expect(repository.createdKeys.first.$1, 'Mon script');
      expect(repository.createdKeys.first.$2, <ApiKeyScope>{ApiKeyScope.read});

      // Le secret est montré, une seule fois.
      expect(find.text(strings.apiKeysSecret), findsOneWidget);
      expect(find.text(strings.apiKeysSecretWarning), findsOneWidget);
      expect(find.text(fakeApiKeySecret), findsOneWidget);
    });

    testWidgets('ne montre plus le secret quand l’écran est rouvert', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1200));
      final FakeWebhookRepository repository = FakeWebhookRepository();
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const ApiKeysScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(ApiKeysScreen),
      );

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.apiKeysCreate),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(LimpidTextField), 'Mon script');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(LimpidDialog),
          matching: find.widgetWithText(LimpidButton, strings.apiKeysCreate),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(fakeApiKeySecret), findsOneWidget);

      // L'auteur referme le panneau : le secret est perdu.
      await tester.tap(
        find.widgetWithText(LimpidButton, strings.actionContinue),
      );
      await tester.pumpAndSettle();
      expect(find.text(fakeApiKeySecret), findsNothing);

      // L'écran rouvert ne sait toujours pas le secret.
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const SizedBox()),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const ApiKeysScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text(fakeApiKeySecret), findsNothing);
      expect(find.text(strings.apiKeysSecret), findsNothing);
    });

    testWidgets('renouvelle le secret d’une clé', (tester) async {
      useSurface(tester, const Size(900, 1200));
      final FakeWebhookRepository repository = FakeWebhookRepository(
        keys: <ApiKey>[fakeApiKey],
      );
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const ApiKeysScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(ApiKeysScreen),
      );

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.apiKeysRotate),
      );
      await tester.pumpAndSettle();

      expect(repository.rotatedKeys, <String>['key-1']);
      expect(find.text(strings.apiKeysSecret), findsOneWidget);
      expect(find.text(fakeApiKeySecret), findsOneWidget);
    });

    testWidgets('supprime une clé après confirmation', (tester) async {
      useSurface(tester, const Size(900, 1200));
      final FakeWebhookRepository repository = FakeWebhookRepository(
        keys: <ApiKey>[fakeApiKey],
      );
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const ApiKeysScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(ApiKeysScreen),
      );

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.apiKeysDelete),
      );
      await tester.pumpAndSettle();

      // La fenêtre demande confirmation : rien n'est supprimé avant.
      expect(repository.deletedKeys, isEmpty);
      expect(find.byType(LimpidDialog), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(LimpidDialog),
          matching: find.widgetWithText(LimpidButton, strings.apiKeysDelete),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.deletedKeys, <String>['key-1']);
      expect(find.text('Intégration'), findsNothing);
    });

    testWidgets('ne supprime rien quand l’auteur renonce', (tester) async {
      useSurface(tester, const Size(900, 1200));
      final FakeWebhookRepository repository = FakeWebhookRepository(
        keys: <ApiKey>[fakeApiKey],
      );
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const ApiKeysScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(ApiKeysScreen),
      );

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.apiKeysDelete),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(LimpidButton, strings.actionCancel));
      await tester.pumpAndSettle();

      expect(repository.deletedKeys, isEmpty);
      expect(find.text('Intégration'), findsOneWidget);
    });

    testWidgets('dit que le service n’est pas configuré', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        webhooksHarness(
          repository: const UnavailableWebhookRepository(),
          home: const ApiKeysScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(ApiKeysScreen),
      );

      expect(find.text(strings.demoModeTitle), findsOneWidget);
      expect(
        find.widgetWithText(LimpidButton, strings.apiKeysCreate),
        findsNothing,
      );
    });

    testWidgets('dit que la formule Studio est nécessaire', (tester) async {
      useSurface(tester, const Size(900, 900));
      final FakeWebhookRepository repository = FakeWebhookRepository()
        ..error = const StudioPlanRequiredException();
      await tester.pumpWidget(
        webhooksHarness(repository: repository, home: const ApiKeysScreen()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(
        tester,
        find.byType(ApiKeysScreen),
      );

      // Le refus se lit comme un refus : jamais une liste vide.
      expect(find.text(strings.webhooksStudioOnly), findsOneWidget);
      expect(find.text(strings.apiKeysEmpty), findsNothing);
    });
  });
}
