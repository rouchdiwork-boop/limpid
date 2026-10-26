import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/features/publication/purchases/book_file_saver.dart';
import 'package:limpid_app/src/features/publication/purchases/purchases_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../sale/fakes.dart';

/// L'identifiant du livre des tests.
const String bookId = 'heures';

void main() {
  /// Donne au test une surface assez grande pour l'ecran des achats.
  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Enveloppe l'ecran dans les deps et le theme dont il a besoin.
  Widget harness({
    required Widget child,
    BookSaleRepository? sales,
    BookFileSaver? saver,
  }) {
    return ProviderScope(
      overrides: [
        bookSaleRepositoryProvider.overrideWithValue(
          sales ?? FakeBookSaleRepository(),
        ),
        bookFileSaverProvider.overrideWithValue(saver ?? FakeBookFileSaver()),
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
    return AppLocalizations.of(tester.element(find.byType(PurchasesScreen)));
  }

  group('l\'ecran des livres achetes', () {
    testWidgets('montre les livres achetes', (tester) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBookSaleRepository sales = FakeBookSaleRepository(
        purchased: <BookPurchase>[fakeBookPurchase()],
      );

      await tester.pumpWidget(
        harness(child: const PurchasesScreen(), sales: sales),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.text(strings.purchasesTitle), findsOneWidget);
      expect(find.byKey(purchaseTileKey(bookId)), findsOneWidget);
      expect(find.text('Les Heures de Cendre'), findsOneWidget);
    });

    testWidgets('montre un etat vide quand le compte n\'a rien achete', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBookSaleRepository sales = FakeBookSaleRepository();

      await tester.pumpWidget(
        harness(child: const PurchasesScreen(), sales: sales),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.text(strings.purchasesEmpty), findsOneWidget);
      expect(find.byKey(purchaseTileKey(bookId)), findsNothing);
    });

    testWidgets('le bouton telecharger demande une adresse et telecharge', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBookSaleRepository sales = FakeBookSaleRepository(
        purchased: <BookPurchase>[fakeBookPurchase()],
        file: fakeBookFile(fileName: 'heures.epub'),
      );
      final FakeBookFileSaver saver = FakeBookFileSaver();

      await tester.pumpWidget(
        harness(child: const PurchasesScreen(), sales: sales, saver: saver),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(purchaseDownloadKey(bookId)));
      await tester.pumpAndSettle();

      expect(sales.downloadCalls, 1);
      expect(saver.saved, hasLength(1));
      expect(saver.saved.single.fileName, 'heures.epub');
      expect(saver.saved.single.bytes, isNotEmpty);
    });

    testWidgets('le lien expire dit qu\'il faut en demander un autre', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBookSaleRepository sales = FakeBookSaleRepository(
        purchased: <BookPurchase>[fakeBookPurchase()],
        file: fakeBookFile(
          expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        ),
      );
      final FakeBookFileSaver saver = FakeBookFileSaver();

      await tester.pumpWidget(
        harness(child: const PurchasesScreen(), sales: sales, saver: saver),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(purchaseDownloadKey(bookId)));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.text(strings.purchasesLinkExpired), findsOneWidget);
      expect(find.text(strings.purchasesRenewLink), findsOneWidget);
    });

    testWidgets('un telechargement refuse n\'est jamais un fichier', (
      tester,
    ) async {
      useSurface(tester, const Size(1000, 1400));
      final FakeBookSaleRepository sales = FakeBookSaleRepository(
        purchased: <BookPurchase>[fakeBookPurchase()],
      )..downloadError = StateError('le serveur a refuse le telechargement');
      final FakeBookFileSaver saver = FakeBookFileSaver();

      await tester.pumpWidget(
        harness(child: const PurchasesScreen(), sales: sales, saver: saver),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(purchaseDownloadKey(bookId)));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(saver.saved, isEmpty);
      expect(find.text(strings.purchasesDownloadFailed), findsOneWidget);
    });
  });
}
