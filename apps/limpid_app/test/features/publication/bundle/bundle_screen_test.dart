import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/bundle_repository.dart';
import 'package:limpid_app/src/features/billing/billing_formatters.dart';
import 'package:limpid_app/src/features/publication/bundle/bundle_routes.dart';
import 'package:limpid_app/src/features/publication/bundle/bundle_screen.dart';
import 'package:limpid_app/src/features/publication/sale/payment_opener.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';

/// L'identifiant du bundle des tests.
const String bundleId = 'bundle-1';

void main() {
  /// Donne au test une surface assez grande pour la page du bundle.
  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Enveloppe l'ecran dans les deps et le theme dont il a besoin.
  Widget harness({
    required Widget child,
    BundleRepository? bundles,
    PaymentOpener? opener,
  }) {
    return ProviderScope(
      overrides: [
        bundleRepositoryProvider.overrideWithValue(
          bundles ?? FakeBundleRepository(),
        ),
        if (opener != null) paymentOpenerProvider.overrideWithValue(opener),
      ],
      child: MaterialApp(
        theme: LimpidTheme.of(LimpidThemeVariant.paper),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  /// Les chaines de l'interface, lues depuis l'ecran rendu.
  AppLocalizations stringsOf(WidgetTester tester) {
    return AppLocalizations.of(tester.element(find.byType(BundleScreen)));
  }

  group('la page d\'un bundle', () {
    testWidgets('montre les livres du bundle et son prix', (tester) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBundleRepository bundles = FakeBundleRepository(
        bundle: fakeBundle(),
      );

      await tester.pumpWidget(
        harness(
          child: const BundleScreen(bundleId: bundleId),
          bundles: bundles,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(bundleTitleKey), findsOneWidget);
      expect(find.text('Les deux livres'), findsOneWidget);
      expect(find.text('Les Heures de Cendre'), findsOneWidget);
      expect(find.text('La Nuit des Savoirs'), findsOneWidget);
      expect(find.byKey(bundlePriceKey), findsOneWidget);
      expect(find.text(formatPrice(1500)), findsOneWidget);
    });

    testWidgets('ne montre aucun prix quand le bundle n\'est pas en vente', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBundleRepository bundles = FakeBundleRepository();

      await tester.pumpWidget(
        harness(
          child: const BundleScreen(bundleId: bundleId),
          bundles: bundles,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.byKey(bundlePriceKey), findsNothing);
      expect(find.byKey(bundleBuyKey), findsNothing);
      expect(find.text(strings.saleNotForSale), findsOneWidget);
    });

    testWidgets('le bouton acheter commande le bundle et ouvre l\'adresse', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBundleRepository bundles = FakeBundleRepository(
        bundle: fakeBundle(),
      );
      final FakeBundlePaymentOpener opener = FakeBundlePaymentOpener();

      await tester.pumpWidget(
        harness(
          child: const BundleScreen(bundleId: bundleId),
          bundles: bundles,
          opener: opener,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(bundleBuyKey));
      await tester.pumpAndSettle();

      expect(bundles.orderCalls, 1);
      expect(bundles.orderedBundleId, bundleId);
      expect(bundles.orderedSuccessPath, BundleRoutes.paymentReturn(bundleId));
      expect(opener.opened, hasLength(1));
      expect(opener.opened.single.toString(), 'https://paiement.test/achat/1');
    });

    testWidgets('le bouton acheter dit que la plateforme ne paie pas', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBundleRepository bundles = FakeBundleRepository(
        bundle: fakeBundle(),
      );
      final FakeBundlePaymentOpener opener = FakeBundlePaymentOpener()
        ..canOpen = false;

      await tester.pumpWidget(
        harness(
          child: const BundleScreen(bundleId: bundleId),
          bundles: bundles,
          opener: opener,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(bundleBuyKey));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(bundles.orderCalls, 1);
      expect(find.text(strings.salePaymentUnavailable), findsOneWidget);
    });

    testWidgets('une commande refusee n\'est jamais un paiement reussi', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBundleRepository bundles = FakeBundleRepository(
        bundle: fakeBundle(),
      )..orderError = StateError('le serveur a refuse la commande');
      final FakeBundlePaymentOpener opener = FakeBundlePaymentOpener();

      await tester.pumpWidget(
        harness(
          child: const BundleScreen(bundleId: bundleId),
          bundles: bundles,
          opener: opener,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(bundleBuyKey));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(opener.opened, isEmpty);
      expect(find.text(strings.saleOrderFailed), findsOneWidget);
    });
  });
}
