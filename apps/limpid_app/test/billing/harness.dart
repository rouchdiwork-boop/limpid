import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/billing/billing_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';

/// Gives the test a viewport of the size it needs.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Builds the billing screen of the test.
///
/// The port of the plans is the only thing the screen reads: the fake is
/// enough.
Widget billingHarness({required FakePlanRepository repository}) {
  return ProviderScope(
    overrides: [planRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const BillingScreen(),
    ),
  );
}

/// The strings of the billing screen.
AppLocalizations stringsOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BillingScreen)));
