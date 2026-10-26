import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/golden.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'golden_fonts.dart';
import 'golden_harness.dart';
import 'golden_subjects.dart';

/// Le temoin **structurel** du design system.
///
/// Pour chaque widget et chaque theme, le test compare le rendu a une
/// description textuelle du rendu : l'arbre des widgets, leurs textes, leurs
/// couleurs resolues, leurs rayons et leurs espacements.
///
/// Ce temoin est **stable partout** : il tourne sous Windows comme sous
/// Linux, et il est donc le contrat de la CI. Le temoin d'image, lui, ne
/// tourne que sur la plateforme qui l'a genere.
void main() {
  setUpAll(loadGoldenFonts);

  test('the design system covers at least thirty widgets', () {
    expect(kGoldenSubjects.length, greaterThanOrEqualTo(30));

    // Chaque widget est couvert une seule fois : deux noms identiques
    // partageraient le meme fichier d'attente et le temoin serait muet.
    final Set<String> names = kGoldenSubjects
        .map((GoldenSubject subject) => subject.name)
        .toSet();
    expect(names.length, kGoldenSubjects.length);
  });

  for (final GoldenSubject subject in kGoldenSubjects) {
    for (final LimpidThemeVariant variant in kGoldenVariants) {
      testWidgets('${subject.name} — ${variant.name}', (
        WidgetTester tester,
      ) async {
        final Key subjectKey = await pumpGoldenSubject(
          tester,
          subject: subject,
          variant: variant,
        );

        final GoldenDescription description = GoldenExtractor.describe(
          tester.element(find.byKey(subjectKey)),
        );

        final GoldenWitness witness = checkGoldenSubject(
          subject: subject,
          variant: variant,
          actual: description.toLines(),
          isUpdating: autoUpdateGoldenFiles,
        );

        expect(witness.isMatching, isTrue, reason: witness.report);
      });
    }
  }
}
