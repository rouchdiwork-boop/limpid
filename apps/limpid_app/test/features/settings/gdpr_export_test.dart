import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../../onboarding/fakes.dart';
import 'fakes.dart';
import 'harness.dart';

void main() {
  testWidgets('l\'export appelle le dépôt et présente le fichier', (
    tester,
  ) async {
    useSurface(tester);
    final FakeGdprRepository gdpr = FakeGdprRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gdprRepositoryProvider.overrideWithValue(gdpr),
          manuscriptRepositoryProvider.overrideWithValue(
            FakeManuscriptRepository(),
          ),
        ],
        child: settingsHarness(),
      ),
    );
    await tester.pumpAndSettle();
    final strings = stringsOf(tester);

    final Finder export = find.text(strings.settingsExportPersonalData);
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pumpAndSettle();

    expect(find.byType(LimpidDialog), findsOneWidget);

    final Finder entry = find.descendant(
      of: find.byType(LimpidDialog),
      matching: find.text(strings.settingsExportPersonalData),
    );
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(gdpr.exportCalls, 1);
    expect(find.text('limpid-donnees.json'), findsOneWidget);
    expect(find.textContaining('audit_log'), findsOneWidget);
  });

  testWidgets('l\'export refuse quand le serveur n\'est pas configuré', (
    tester,
  ) async {
    useSurface(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          manuscriptRepositoryProvider.overrideWithValue(
            FakeManuscriptRepository(),
          ),
        ],
        child: settingsHarness(),
      ),
    );
    await tester.pumpAndSettle();
    final strings = stringsOf(tester);

    expect(
      find.text(strings.settingsExportPersonalDataUnavailable),
      findsWidgets,
    );
    final Finder export = find.text(strings.settingsExportPersonalData);
    final LimpidListTile tile = tester.widget<LimpidListTile>(
      find.ancestor(of: export, matching: find.byType(LimpidListTile)),
    );
    expect(tile.onTap, isNull);
  });

  testWidgets('l\'erreur du serveur est affichée telle quelle', (tester) async {
    useSurface(tester);
    final FakeGdprRepository gdpr = FakeGdprRepository()
      ..error = const ApiValidationException(
        'L\'export a été refusé par le serveur.',
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gdprRepositoryProvider.overrideWithValue(gdpr),
          manuscriptRepositoryProvider.overrideWithValue(
            FakeManuscriptRepository(),
          ),
        ],
        child: settingsHarness(),
      ),
    );
    await tester.pumpAndSettle();
    final strings = stringsOf(tester);

    final Finder export = find.text(strings.settingsExportPersonalData);
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pumpAndSettle();

    final Finder entry = find.descendant(
      of: find.byType(LimpidDialog),
      matching: find.text(strings.settingsExportPersonalData),
    );
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(gdpr.exportCalls, 1);
    expect(find.text('L\'export a été refusé par le serveur.'), findsOneWidget);
  });
}
