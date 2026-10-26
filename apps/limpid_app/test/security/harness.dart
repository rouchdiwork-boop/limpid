import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';
import 'package:limpid_app/src/features/security/two_factor_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Gives the test a viewport of the size it needs.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Builds the security screen of the test.
///
/// The port of the second factor is the only thing the screen reads: the
/// fake is enough.
Widget securityHarness({required TwoFactorRepository repository}) {
  return ProviderScope(
    overrides: [twoFactorRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TwoFactorScreen(),
    ),
  );
}

/// The strings of the security screen.
AppLocalizations stringsOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TwoFactorScreen)));
