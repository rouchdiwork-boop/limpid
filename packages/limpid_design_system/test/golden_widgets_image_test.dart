import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'golden/golden_fonts.dart';
import 'golden/golden_harness.dart';
import 'golden/golden_subjects.dart';

/// Le temoin **d'image** du design system.
///
/// L'image est une preuve pour l'auteur : elle montre ce que le widget
/// ressemble reellement. Elle n'est **pas** un contrat de la CI : une image
/// generee sous Windows ne correspond pas sous Linux, puisque le rendu du
/// texte et l'anticrenelage different.
///
/// Le test est donc **saute** sur toute autre plateforme. Ce qui lie la CI au
/// design system, c'est le temoin structurel.
void main() {
  setUpAll(loadGoldenFonts);

  for (final GoldenSubject subject in kGoldenSubjects) {
    for (final LimpidThemeVariant variant in kGoldenVariants) {
      testWidgets('${subject.name} — ${variant.name}', (
        WidgetTester tester,
      ) async {
        await pumpGoldenSubject(tester, subject: subject, variant: variant);

        await expectLater(
          find.byKey(kGoldenBoundaryKey),
          matchesGoldenFile('goldens/${subject.name}-${variant.name}.png'),
        );
      }, skip: !Platform.isWindows);
    }
  }
}
