import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/admin_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/admin/admin_account_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  group("l'écran du back-office", () {
    testWidgets('montre la liste des comptes et la liste des indicateurs', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1400));
      await tester.pumpWidget(
        adminHarness(
          repository: FakeAdminRepository(
            accounts: <AdminAccount>[fakeAccount, fakePurgedAccount],
            flags: <AdminFeatureFlag>[fakeFlag],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = adminStrings(tester);

      // Les comptes : l'identifiant, l'adresse, la formule et l'usage.
      expect(find.text(strings.adminTitle), findsOneWidget);
      expect(find.text('auteur-1'), findsOneWidget);
      expect(find.text('auteur@exemple.fr'), findsOneWidget);
      expect(find.text('studio'), findsOneWidget);
      expect(find.text(strings.adminAccountProjects(3)), findsOneWidget);
      expect(find.text(strings.adminAccountOperations(12)), findsOneWidget);

      // Les indicateurs.
      expect(find.text(strings.adminFlagsTitle), findsOneWidget);
      expect(find.text('ai_premium'), findsOneWidget);
      expect(find.byType(LimpidSwitch), findsOneWidget);
    });

    testWidgets('active un indicateur : le serveur est appelé, l’état change', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1400));
      final FakeAdminRepository repository = FakeAdminRepository(
        accounts: <AdminAccount>[fakeAccount],
        flags: <AdminFeatureFlag>[fakeFlag],
      );
      await tester.pumpWidget(adminHarness(repository: repository));
      await tester.pumpAndSettle();

      final Finder toggle = find.byType(LimpidSwitch);
      expect(tester.widget<LimpidSwitch>(toggle).value, isFalse);

      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(repository.changes, <(String, bool)>[('ai_premium', true)]);
      expect(tester.widget<LimpidSwitch>(toggle).value, isTrue);
    });

    testWidgets('désactive un indicateur déjà actif', (tester) async {
      useSurface(tester, const Size(900, 1400));
      final FakeAdminRepository repository = FakeAdminRepository(
        flags: <AdminFeatureFlag>[fakeEnabledFlag],
      );
      await tester.pumpWidget(adminHarness(repository: repository));
      await tester.pumpAndSettle();

      final Finder toggle = find.byType(LimpidSwitch);
      expect(tester.widget<LimpidSwitch>(toggle).value, isTrue);

      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(repository.changes, <(String, bool)>[('kdp_publish', false)]);
      expect(tester.widget<LimpidSwitch>(toggle).value, isFalse);
    });

    testWidgets('dit que la page est réservée aux administrateurs', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 900));
      final FakeAdminRepository repository =
          FakeAdminRepository(
              accounts: <AdminAccount>[fakeAccount],
              flags: <AdminFeatureFlag>[fakeFlag],
            )
            ..error = const ApiUnauthorizedException(
              "Cette ressource est réservée à l'administration.",
              statusCode: 403,
            );
      await tester.pumpWidget(adminHarness(repository: repository));
      await tester.pumpAndSettle();

      final AppLocalizations strings = adminStrings(tester);

      // Le refus se lit comme un refus : jamais une liste vide.
      expect(find.text(strings.adminForbiddenTitle), findsWidgets);
      expect(find.text(strings.adminForbiddenMessage), findsWidgets);
      expect(find.text('auteur-1'), findsNothing);
      expect(find.byType(LimpidSwitch), findsNothing);
    });

    testWidgets('dit que le service n’est pas configuré', (tester) async {
      useSurface(tester, const Size(900, 900));
      final FakeAdminRepository repository = FakeAdminRepository()
        ..error = const ServiceUnavailableException();
      await tester.pumpWidget(adminHarness(repository: repository));
      await tester.pumpAndSettle();

      final AppLocalizations strings = adminStrings(tester);

      expect(find.text(strings.demoModeTitle), findsWidgets);
      expect(find.text('auteur-1'), findsNothing);
    });

    testWidgets('dit que le back-office n’est pas câblé', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(adminHarness());
      await tester.pumpAndSettle();

      final AppLocalizations strings = adminStrings(tester);

      expect(find.text(strings.demoModeTitle), findsWidgets);
    });

    testWidgets('montre l’état vide quand le service n’a aucun compte', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(adminHarness(repository: FakeAdminRepository()));
      await tester.pumpAndSettle();

      final AppLocalizations strings = adminStrings(tester);

      expect(find.text(strings.adminAccountsEmpty), findsOneWidget);
      expect(find.text(strings.adminFlagsEmpty), findsOneWidget);
    });

    testWidgets('ouvre le détail d’un compte', (tester) async {
      useSurface(tester, const Size(900, 1400));
      await tester.pumpWidget(
        adminHarness(
          repository: FakeAdminRepository(
            accounts: <AdminAccount>[fakeAccount],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('auteur-1'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminAccountScreen), findsOneWidget);

      final AppLocalizations strings = adminAccountStrings(tester);
      expect(find.text('auteur-1'), findsOneWidget);
      expect(find.text(strings.adminColumnPlan), findsOneWidget);
      expect(find.text(strings.adminAccountLastActivity), findsOneWidget);
      expect(find.text(strings.adminAccountSeats), findsNothing);
    });
  });
}
