import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'golden/reference_fonts.dart';
import 'golden/reference_harness.dart';

/// Le temoin **d'image** des ecrans de reference.
///
/// L'image est une preuve pour l'auteur : elle montre ce que l'ecran
/// ressemble reellement dans les quatre themes. Elle n'est **pas** un
/// contrat de la CI : une image generee sous Windows ne correspond pas sous
/// Linux, puisque le rendu du texte et l'anticrenelage different.
///
/// Le test est donc **saute** sur toute autre plateforme. Ce qui lie la CI
/// aux ecrans, c'est le temoin structurel.
void main() {
  setUpAll(loadReferenceFonts);

  for (final ReferenceScreen screen in kReferenceScreens) {
    for (final LimpidThemeVariant variant in kReferenceVariants) {
      testWidgets('${screen.name} — ${variant.name}', (
        WidgetTester tester,
      ) async {
        await describeReferenceScreen(tester, screen, variant);

        await expectLater(
          find.byKey(kReferenceBoundaryKey),
          matchesGoldenFile('goldens/${screen.name}-${variant.name}.png'),
        );
      }, skip: !Platform.isWindows);
    }
  }
}
