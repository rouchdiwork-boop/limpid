import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  group("l'écran de la double authentification", () {
    testWidgets('montre le second facteur désactivé', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        securityHarness(repository: FakeTwoFactorRepository()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);

      expect(find.text(strings.twoFactorTitle), findsOneWidget);
      expect(find.text(strings.twoFactorStateOff), findsOneWidget);
      expect(find.text(strings.twoFactorEnable), findsOneWidget);
      expect(find.text(strings.twoFactorDisable), findsNothing);
    });

    testWidgets('montre le second facteur activé', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        securityHarness(
          repository: FakeTwoFactorRepository(state: fakeTwoFactorOn),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);

      expect(find.text(strings.twoFactorStateOn), findsOneWidget);
      expect(find.text(strings.twoFactorVerify), findsOneWidget);
      expect(find.text(strings.twoFactorDisable), findsOneWidget);
      expect(find.text(strings.twoFactorEnable), findsNothing);
    });

    testWidgets('dit que la formule exige le second facteur', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        securityHarness(
          repository: FakeTwoFactorRepository(state: fakeTwoFactorRequired),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);

      expect(find.text(strings.twoFactorRequired), findsOneWidget);
      expect(find.text(strings.twoFactorStateOff), findsOneWidget);
      expect(find.text(strings.twoFactorEnable), findsOneWidget);
    });

    testWidgets('dit que le service n’est pas configuré', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        securityHarness(repository: const UnavailableTwoFactorRepository()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);

      expect(find.text(strings.twoFactorUnavailable), findsOneWidget);
      expect(find.text(strings.twoFactorEnable), findsNothing);
    });

    testWidgets('désactive le second facteur du compte', (tester) async {
      useSurface(tester, const Size(900, 900));
      final FakeTwoFactorRepository repository = FakeTwoFactorRepository(
        state: fakeTwoFactorOn,
      );
      await tester.pumpWidget(securityHarness(repository: repository));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      await tester.tap(find.text(strings.twoFactorDisable));
      await tester.pumpAndSettle();

      expect(repository.disableCount, 1);
      expect(find.text(strings.twoFactorStateOff), findsOneWidget);
    });
  });

  group("l'inscription du second facteur", () {
    testWidgets('montre le secret et les codes de récupération', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1200));
      final FakeTwoFactorRepository repository = FakeTwoFactorRepository();
      await tester.pumpWidget(securityHarness(repository: repository));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);

      // L'inscription montre le secret et l'adresse de l'application
      // d'authentification.
      await tester.tap(find.text(strings.twoFactorEnable));
      await tester.pumpAndSettle();

      expect(find.text(strings.twoFactorSecretLabel), findsOneWidget);
      expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
      expect(
        find.text('otpauth://totp/Limpid:auteur@test?secret=JBSWY3DPEHPK3PXP'),
        findsOneWidget,
      );

      // La confirmation rend les codes de récupération, une seule fois.
      await tester.enterText(find.byType(LimpidTextField), '123456');
      await tester.tap(find.text(strings.twoFactorConfirm));
      await tester.pumpAndSettle();

      expect(repository.confirmed, <String>['123456']);
      expect(find.text(strings.twoFactorRecoveryCodes), findsOneWidget);
      expect(find.text('limpid-aaaa-bbbb'), findsOneWidget);
      expect(find.text('limpid-cccc-dddd'), findsOneWidget);

      // Les codes ne sont pas rendus une seconde fois : quitter le panneau
      // les perd.
      await tester.tap(find.text(strings.actionContinue));
      await tester.pumpAndSettle();

      expect(find.text('limpid-aaaa-bbbb'), findsNothing);
      expect(find.text(strings.twoFactorStateOn), findsOneWidget);
    });

    testWidgets('refuse un code faux sans rien activer', (tester) async {
      useSurface(tester, const Size(900, 1200));
      final FakeTwoFactorRepository repository = FakeTwoFactorRepository()
        ..confirmError = const ApiValidationException('Le code est invalide.');
      await tester.pumpWidget(securityHarness(repository: repository));
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      await tester.tap(find.text(strings.twoFactorEnable));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(LimpidTextField), '000000');
      await tester.tap(find.text(strings.twoFactorConfirm));
      await tester.pumpAndSettle();

      expect(find.text(strings.twoFactorInvalidCode), findsOneWidget);
      expect(repository.confirmed, isEmpty);
      expect(repository.state.enabled, isFalse);
      expect(find.text(strings.twoFactorRecoveryCodes), findsNothing);
    });
  });
}
