import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/features/publication/sale/payment_return_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';

/// L'identifiant du livre des tests.
const String bookId = 'heures';

void main() {
  /// Enveloppe l'ecran dans les deps et le theme dont il a besoin.
  Widget harness({required Widget child, BookSaleRepository? sales}) {
    return ProviderScope(
      overrides: [
        bookSaleRepositoryProvider.overrideWithValue(
          sales ?? FakeBookSaleRepository(),
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
    return AppLocalizations.of(
      tester.element(find.byType(PaymentReturnScreen)),
    );
  }

  group('l\'ecran de retour du paiement', () {
    testWidgets(
      'dit que le livre est dans les achats quand la liste le porte',
      (tester) async {
        final FakeBookSaleRepository sales = FakeBookSaleRepository(
          purchased: <BookPurchase>[fakeBookPurchase()],
        );

        await tester.pumpWidget(
          harness(
            child: const PaymentReturnScreen(projectId: bookId),
            sales: sales,
          ),
        );
        await tester.pumpAndSettle();

        final AppLocalizations strings = stringsOf(tester);
        expect(find.text(strings.paymentReturnSuccess), findsOneWidget);
        expect(find.text(strings.paymentReturnFailure), findsNothing);
      },
    );

    testWidgets('ne pretend pas que l\'achat a abouti quand la liste le nie', (
      tester,
    ) async {
      final FakeBookSaleRepository sales = FakeBookSaleRepository(
        purchased: <BookPurchase>[fakeBookPurchase(projectId: 'autre-livre')],
      );

      await tester.pumpWidget(
        harness(
          child: const PaymentReturnScreen(projectId: bookId),
          sales: sales,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.text(strings.paymentReturnFailure), findsOneWidget);
      expect(find.text(strings.paymentReturnSuccess), findsNothing);
      expect(sales.purchasesCalls, 1);
    });

    testWidgets('ne pretend pas que l\'achat a abouti sans liste du tout', (
      tester,
    ) async {
      final FakeBookSaleRepository sales = FakeBookSaleRepository();

      await tester.pumpWidget(
        harness(
          child: const PaymentReturnScreen(projectId: bookId),
          sales: sales,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.text(strings.paymentReturnFailure), findsOneWidget);
      expect(find.text(strings.paymentReturnSuccess), findsNothing);
    });
  });
}
