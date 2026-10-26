import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/limpid_app.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/auth/local_auth_store.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/billing/billing_screen.dart';
import 'package:limpid_app/src/features/billing/billing_side_panel.dart';
import 'package:limpid_app/src/features/billing/plan_card.dart';
import 'package:limpid_app/src/features/billing/usage_panel.dart';
import 'package:limpid_core/limpid_core.dart';

import '../features/publication/fakes.dart';
import 'fakes.dart';
import 'harness.dart';

/// L'espace insécable qui sépare un nombre de son unité.
const String kNoBreak = ' ';

void main() {
  group("l'écran de formule", () {
    testWidgets('affiche les quatre formules avec leurs limites', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      await tester.pumpWidget(billingHarness(repository: FakePlanRepository()));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);

      expect(find.byType(PlanCard), findsNWidgets(4));
      expect(find.text('GRATUIT'), findsOneWidget);
      expect(find.text('ÉCRIVAIN'), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('STUDIO'), findsOneWidget);

      // Les limites sont en chiffres : l'auteur sait ce qu'il perd.
      expect(find.text('200 000'), findsOneWidget);
      expect(find.text('500${kNoBreak}Mo'), findsOneWidget);
      expect(find.textContaining(strings.billingSeats(5)), findsOneWidget);
    });

    testWidgets('se réduit en une colonne sur un écran étroit', (tester) async {
      useSurface(tester, const Size(420, 900));
      await tester.pumpWidget(billingHarness(repository: FakePlanRepository()));
      await tester.pumpAndSettle();

      // Les quatre formules sont là ; le panneau de facturation passe sous
      // elles. L'écran ne déborde pas.
      expect(find.byType(PlanCard), findsNWidgets(4));
      await tester.scrollUntilVisible(find.byType(BillingSidePanel), 400);
      expect(find.byType(BillingSidePanel), findsOneWidget);
    });

    testWidgets('marque la formule du compte comme formule actuelle', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      await tester.pumpWidget(billingHarness(repository: FakePlanRepository()));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);

      expect(find.text(strings.billingCurrentPlan), findsOneWidget);
      expect(find.text(strings.billingManagePlan), findsOneWidget);
      expect(find.text(strings.billingChoosePlan), findsNWidgets(3));
    });

    testWidgets('remplit les jauges avec la consommation et la limite', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      await tester.pumpWidget(billingHarness(repository: FakePlanRepository()));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      final Finder panel = find.byType(UsagePanel);

      expect(find.text(strings.billingUsageTitle), findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.text(strings.billingWords)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.text(strings.billingAiRewrites),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text(strings.billingStorage)),
        findsOneWidget,
      );

      // La jauge de l'usage de l'IA : 341 sur 1 000.
      final LinearProgressIndicator bar = tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator).at(1),
          );
      expect(bar.value, closeTo(0.341, 0.0001));

      // La figure porte la consommation et la limite.
      expect(find.text(strings.billingUsageOf('1 000', '341')), findsOneWidget);
      expect(
        find.text(strings.billingUsageOf('1${kNoBreak}Go', '42${kNoBreak}Mo')),
        findsOneWidget,
      );
    });

    testWidgets('dit que le service n’est pas configuré quand le port échoue', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final FakePlanRepository repository = FakePlanRepository()
        ..error = const ServiceUnavailableException();

      await tester.pumpWidget(billingHarness(repository: repository));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);

      expect(find.text(strings.billingUnavailable), findsOneWidget);
      expect(find.byType(PlanCard), findsNothing);
    });

    testWidgets('affiche le prix annuel de la formule qui le propose', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      await tester.pumpWidget(billingHarness(repository: FakePlanRepository()));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);

      expect(find.text(strings.billingMonthly), findsOneWidget);
      expect(
        find.text('${strings.billingAnnual} ${strings.billingAnnualDiscount}'),
        findsOneWidget,
      );

      await tester.tap(
        find.text('${strings.billingAnnual} ${strings.billingAnnualDiscount}'),
      );
      await tester.pumpAndSettle();

      // Le cycle annuel ne concerne que Studio : les autres formules gardent
      // leur prix mensuel, l'écran n'invente pas de prix annuel.
      expect(find.text('499,00$kNoBreak€'), findsOneWidget);
      expect(find.text('9,99$kNoBreak€'), findsOneWidget);
      expect(find.textContaining(strings.billingPerYear), findsOneWidget);
    });

    testWidgets('ouvre une session de paiement quand l’auteur choisit', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final FakePlanRepository repository = FakePlanRepository();

      await tester.pumpWidget(billingHarness(repository: repository));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);

      // La deuxième carte est la formule Écrivain : elle se paie.
      final Finder button = find.text(strings.billingChoosePlan).at(1);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(repository.paid, <SubscriptionPlan>[SubscriptionPlan.writer]);
      expect(find.text('https://checkout.test/session/1'), findsWidgets);
    });

    testWidgets(
      'dit que la formule ne permet pas l’action quand le quota est atteint',
      (tester) async {
        useSurface(tester, const Size(1440, 1100));
        final FakePlanRepository repository = FakePlanRepository()
          ..changeError = const ApiValidationException(
            'Le quota est atteint.',
            code: 'quota_exceeded',
          );

        await tester.pumpWidget(billingHarness(repository: repository));
        await tester.pumpAndSettle();

        final AppLocalizations strings = stringsOf(tester);

        // La première carte est la formule gratuite : elle se change sans
        // paiement, et le serveur refuse.
        await tester.tap(find.text(strings.billingChoosePlan).first);
        await tester.pumpAndSettle();

        expect(
          find.text(strings.billingQuotaReached('Gratuit')),
          findsOneWidget,
        );
      },
    );
  });

  group('la navigation', () {
    testWidgets('mène à l’écran de formule', (tester) async {
      final DemoAuthRepository auth = DemoAuthRepository(
        store: InMemoryLocalAuthStore(),
      );
      await auth.sendMagicLink('camille@atelier-sable.fr');

      final ProviderContainer container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          manuscriptRepositoryProvider.overrideWithValue(
            FakePublicationRepository(),
          ),
          planRepositoryProvider.overrideWithValue(FakePlanRepository()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const LimpidApp(),
        ),
      );
      // Le tableau de bord se charge : l'écran ne se stabilise jamais. La
      // navigation se fait donc image par image.
      await tester.pump();

      final GoRouter router = container.read(appRouterProvider);
      router.go(AppRoutes.subscription);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/abonnement',
      );
      expect(find.byType(BillingScreen), findsOneWidget);
    });
  });
}
