import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../../onboarding/fakes.dart';
import 'fakes.dart';
import 'harness.dart';

void main() {
  testWidgets('la suppression demande confirmation avant d\'envoyer', (
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

    final Finder deletion = find.text(strings.settingsDeleteAccount);
    await tester.ensureVisible(deletion);
    await tester.tap(deletion);
    await tester.pumpAndSettle();

    expect(find.byType(LimpidDialog), findsOneWidget);
    expect(gdpr.deletionCalls, 0);

    final Finder confirm = find.widgetWithText(
      LimpidButton,
      strings.settingsDeleteAccount,
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(gdpr.deletionCalls, 1);
  });

  testWidgets('la suppression est annulée quand l\'auteur refuse', (
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

    final Finder deletion = find.text(strings.settingsDeleteAccount);
    await tester.ensureVisible(deletion);
    await tester.tap(deletion);
    await tester.pumpAndSettle();

    final Finder cancel = find.widgetWithText(
      LimpidButton,
      strings.actionCancel,
    );
    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(gdpr.deletionCalls, 0);
  });

  testWidgets('la suppression annonce la date de la purge', (tester) async {
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

    final Finder deletion = find.text(strings.settingsDeleteAccount);
    await tester.ensureVisible(deletion);
    await tester.tap(deletion);
    await tester.pumpAndSettle();

    final Finder confirm = find.widgetWithText(
      LimpidButton,
      strings.settingsDeleteAccount,
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(gdpr.deletionCalls, 1);
    expect(find.text(strings.settingsDeleteAccountScheduled), findsWidgets);
  });

  testWidgets('l\'erreur du serveur est affichée telle quelle', (tester) async {
    useSurface(tester);
    final FakeGdprRepository gdpr = FakeGdprRepository()
      ..error = const ApiValidationException(
        'La suppression du compte a été refusée.',
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

    final Finder deletion = find.text(strings.settingsDeleteAccount);
    await tester.ensureVisible(deletion);
    await tester.tap(deletion);
    await tester.pumpAndSettle();

    final Finder confirm = find.widgetWithText(
      LimpidButton,
      strings.settingsDeleteAccount,
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(gdpr.deletionCalls, 1);
    expect(
      find.text('La suppression du compte a été refusée.'),
      findsOneWidget,
    );
  });

  testWidgets('la suppression est impossible sans serveur', (tester) async {
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

    final Finder deletion = find.text(strings.settingsDeleteAccount);
    final LimpidListTile tile = tester.widget<LimpidListTile>(
      find.ancestor(of: deletion, matching: find.byType(LimpidListTile)),
    );
    expect(tile.onTap, isNull);
    expect(find.text(strings.settingsAccountDeletionUnavailable), findsWidgets);
  });
}
