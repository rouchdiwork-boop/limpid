import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/features/billing/billing_formatters.dart';
import 'package:limpid_app/src/features/publication/publication_routes.dart';
import 'package:limpid_app/src/features/publication/sale/book_sale_screen.dart';
import 'package:limpid_app/src/features/publication/sale/payment_opener.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../fakes.dart';
import 'fakes.dart';

/// L'identifiant du livre des tests.
const String bookId = 'heures';

void main() {
  /// Donne au test une surface assez grande pour la page de vente.
  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Enveloppe l'ecran dans les deps et le theme dont il a besoin.
  Widget harness({
    required Widget child,
    BookSaleRepository? sales,
    PaymentOpener? opener,
  }) {
    return ProviderScope(
      overrides: [
        bookSaleRepositoryProvider.overrideWithValue(
          sales ?? FakeBookSaleRepository(),
        ),
        if (opener != null) paymentOpenerProvider.overrideWithValue(opener),
        publicationRepositoryProvider.overrideWithValue(
          FakePublicationPageRepository(),
        ),
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
    return AppLocalizations.of(tester.element(find.byType(BookSaleScreen)));
  }

  group('la page de vente d\'un livre', () {
    testWidgets('montre le prix du livre', (tester) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBookSaleRepository sales = FakeBookSaleRepository(
        sale: fakeBookSale(priceInCents: 1290),
      );

      await tester.pumpWidget(
        harness(
          child: const BookSaleScreen(projectId: bookId),
          sales: sales,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(bookSalePriceKey), findsOneWidget);
      expect(find.text(formatPrice(1290)), findsOneWidget);
    });

    testWidgets('ne montre aucun prix quand le livre n\'est pas en vente', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBookSaleRepository sales = FakeBookSaleRepository();

      await tester.pumpWidget(
        harness(
          child: const BookSaleScreen(projectId: bookId),
          sales: sales,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.byKey(bookSalePriceKey), findsNothing);
      expect(find.byKey(bookSaleBuyKey), findsNothing);
      expect(find.text(strings.saleNotForSale), findsOneWidget);
    });

    testWidgets('le bouton acheter commande le livre et ouvre l\'adresse', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBookSaleRepository sales = FakeBookSaleRepository(
        sale: fakeBookSale(),
      );
      final FakePaymentOpener opener = FakePaymentOpener();

      await tester.pumpWidget(
        harness(
          child: const BookSaleScreen(projectId: bookId),
          sales: sales,
          opener: opener,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(bookSaleBuyKey));
      await tester.pumpAndSettle();

      expect(sales.orderCalls, 1);
      expect(sales.orderedProjectId, bookId);
      expect(sales.orderedSuccessPath, PublicationRoutes.paymentReturn(bookId));
      expect(opener.opened, hasLength(1));
      expect(opener.opened.single.toString(), 'https://paiement.test/achat/1');
    });

    testWidgets('le bouton acheter dit que la plateforme ne paie pas', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBookSaleRepository sales = FakeBookSaleRepository(
        sale: fakeBookSale(),
      );
      final FakePaymentOpener opener = FakePaymentOpener()..canOpen = false;

      await tester.pumpWidget(
        harness(
          child: const BookSaleScreen(projectId: bookId),
          sales: sales,
          opener: opener,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(bookSaleBuyKey));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(sales.orderCalls, 1);
      expect(find.text(strings.salePaymentUnavailable), findsOneWidget);
    });

    testWidgets('un livre gratuit ne demande pas de paiement', (tester) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBookSaleRepository sales = FakeBookSaleRepository(
        sale: fakeBookSale(priceInCents: 0),
        orderToServe: const BookOrder(
          projectId: bookId,
          amountInCents: 0,
          currency: 'eur',
          isFree: true,
          isGranted: true,
        ),
      );
      final FakePaymentOpener opener = FakePaymentOpener();

      await tester.pumpWidget(
        harness(
          child: const BookSaleScreen(projectId: bookId),
          sales: sales,
          opener: opener,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(bookSaleBuyKey));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(opener.opened, isEmpty);
      expect(find.text(strings.saleFreeGranted), findsOneWidget);
    });

    testWidgets('une commande refusee n\'est jamais un paiement reussi', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBookSaleRepository sales = FakeBookSaleRepository(
        sale: fakeBookSale(),
      )..orderError = StateError('le serveur a refuse la commande');
      final FakePaymentOpener opener = FakePaymentOpener();

      await tester.pumpWidget(
        harness(
          child: const BookSaleScreen(projectId: bookId),
          sales: sales,
          opener: opener,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(bookSaleBuyKey));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(opener.opened, isEmpty);
      expect(find.text(strings.saleOrderFailed), findsOneWidget);
    });
  });
}
