import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/golden.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'reference_fonts.dart';
import 'reference_harness.dart';

/// Le temoin **structurel** des ecrans de reference.
///
/// Pour chaque ecran et chaque theme, le test compare le rendu a une
/// description textuelle du rendu, et verifie que l'ecran rend **complet** :
/// il tient dans la surface donnee, il ne deborde pas et aucun texte n'est
/// tronque.
///
/// Ce temoin est **stable partout** : il tourne sous Windows comme sous
/// Linux, et il est donc le contrat de la CI. Le temoin d'image, lui, ne
/// tourne que sur la plateforme qui l'a genere.
void main() {
  setUpAll(loadReferenceFonts);

  test('the application has five reference screens', () {
    expect(kReferenceScreens, hasLength(5));

    final Set<String> names = kReferenceScreens
        .map((ReferenceScreen screen) => screen.name)
        .toSet();
    expect(names.length, kReferenceScreens.length);
  });

  for (final ReferenceScreen screen in kReferenceScreens) {
    for (final LimpidThemeVariant variant in kReferenceVariants) {
      testWidgets('${screen.name} — ${variant.name}', (
        WidgetTester tester,
      ) async {
        final GoldenDescription description = await describeReferenceScreen(
          tester,
          screen,
          variant,
        );

        expectScreenRendersCompletely(tester, screen);

        final GoldenWitness witness = checkReferenceScreen(
          screen: screen,
          variant: variant,
          actual: description.toLines(),
          isUpdating: autoUpdateGoldenFiles,
        );

        expect(witness.isMatching, isTrue, reason: witness.report);
      });
    }
  }
}
