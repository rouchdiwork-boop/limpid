import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/features/auth/widgets/auth_form.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Gives the test a viewport large enough for the desktop layout.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  Widget harness() {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(DemoAuthRepository()),
      ],
      child: MaterialApp(
        theme: LimpidTheme.of(LimpidThemeVariant.paper),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: AuthForm(mode: AuthFormMode.signIn)),
      ),
    );
  }

  testWidgets('an empty address is refused', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final strings = AppLocalizations.of(tester.element(find.byType(AuthForm)));

    await tester.tap(find.text(strings.actionSendLink));
    await tester.pumpAndSettle();

    expect(find.text(strings.errorEmptyEmail), findsOneWidget);
  });

  testWidgets('a malformed address is refused', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final strings = AppLocalizations.of(tester.element(find.byType(AuthForm)));

    await tester.enterText(find.byType(LimpidTextField), 'pas-une-adresse');
    await tester.tap(find.text(strings.actionSendLink));
    await tester.pumpAndSettle();

    expect(find.text(strings.errorInvalidEmail), findsOneWidget);
  });

  testWidgets('a valid address sends the magic link', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final strings = AppLocalizations.of(tester.element(find.byType(AuthForm)));

    await tester.enterText(
      find.byType(LimpidTextField),
      'camille@atelier-sable.fr',
    );
    await tester.tap(find.text(strings.actionSendLink));
    await tester.pumpAndSettle();

    expect(find.text(strings.linkSentTitle), findsOneWidget);
    expect(
      find.text(strings.linkSentMessage('camille@atelier-sable.fr')),
      findsOneWidget,
    );
  });
}
