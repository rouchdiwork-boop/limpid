import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Gives the test a viewport of the size it needs.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Builds the screen of the test.
///
/// The port of the webhooks is the only thing the screens read : the fake
/// is enough.
Widget webhooksHarness({
  required WebhookRepository repository,
  required Widget home,
}) {
  return ProviderScope(
    overrides: [webhookRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

/// The strings of the screen under test.
AppLocalizations stringsOf(WidgetTester tester, Finder finder) =>
    AppLocalizations.of(tester.element(finder));
