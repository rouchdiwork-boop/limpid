import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/limpid_app.dart';
import 'package:limpid_app/src/app/theme_controller.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

void main() {
  testWidgets(
    'the application starts on the sign-in screen when nobody is signed in',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: LimpidApp()));
      await tester.pumpAndSettle();

      final strings = AppLocalizations.of(
        tester.element(find.byType(Scaffold).first),
      );

      expect(find.text(strings.signInTitle), findsOneWidget);
      expect(find.text(strings.fieldEmail), findsOneWidget);
      expect(find.text(strings.actionSendLink), findsOneWidget);
    },
  );

  testWidgets('the sign-up screen is reachable from the sign-in screen', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: LimpidApp()));
    await tester.pumpAndSettle();

    final strings = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );

    await tester.tap(find.text(strings.signInCreateAccount));
    await tester.pumpAndSettle();

    expect(find.text(strings.signUpTitle), findsOneWidget);
    expect(find.text(strings.fieldAuthorName), findsOneWidget);
  });

  testWidgets('the theme controller switches the applied theme', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: LimpidApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    final before = container.read(themeControllerProvider);
    expect(before, LimpidThemeVariant.paper);

    container
        .read(themeControllerProvider.notifier)
        .select(LimpidThemeVariant.night);
    await tester.pumpAndSettle();

    expect(container.read(themeControllerProvider), LimpidThemeVariant.night);

    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.brightness, Brightness.dark);
  });
}
