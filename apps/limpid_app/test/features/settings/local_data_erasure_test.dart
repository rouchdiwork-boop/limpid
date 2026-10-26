import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_manuscript_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/settings/settings_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../../data/support.dart';
import '../../onboarding/fakes.dart';
import 'fakes.dart';
import 'harness.dart';

void main() {
  testWidgets(
    'la déconnexion demande si les données locales doivent être effacées',
    (tester) async {
      useSurface(tester);
      final FakeAuthRepository auth = FakeAuthRepository();
      int eraseCalls = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            manuscriptRepositoryProvider.overrideWithValue(
              FakeManuscriptRepository(),
            ),
            localDataEraserProvider.overrideWithValue(() async {
              eraseCalls++;
            }),
          ],
          child: settingsHarness(),
        ),
      );
      await tester.pumpAndSettle();
      final strings = stringsOf(tester);

      final Finder signOut = find.widgetWithText(
        LimpidButton,
        strings.actionSignOut,
      );
      await tester.ensureVisible(signOut);
      await tester.tap(signOut);
      await tester.pumpAndSettle();

      expect(find.byType(LimpidDialog), findsOneWidget);
      expect(find.text(strings.settingsEraseLocalDataTitle), findsOneWidget);
      expect(eraseCalls, 0);
      expect(auth.signOutCalls, 0);

      final Finder keep = find.widgetWithText(
        LimpidButton,
        strings.settingsEraseLocalDataKeep,
      );
      await tester.tap(keep);
      await tester.pumpAndSettle();

      expect(eraseCalls, 0);
      expect(auth.signOutCalls, 1);
    },
  );

  testWidgets('effacer les données locales vide la bibliothèque', (
    tester,
  ) async {
    useSurface(tester);
    final AppDatabase database = await openMemoryDatabase();
    addTearDown(database.close);
    final LocalManuscriptRepository manuscripts = LocalManuscriptRepository(
      database: database,
      author: const AuthorId('author-1'),
    );
    await manuscripts.createProject(title: 'Les Heures de Cendre');
    expect(await manuscripts.listProjects(), hasLength(1));
    final FakeAuthRepository auth = FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          manuscriptRepositoryProvider.overrideWithValue(manuscripts),
          localDataEraserProvider.overrideWithValue(database.wiper.wipe),
        ],
        child: settingsHarness(),
      ),
    );
    await tester.pumpAndSettle();
    final strings = stringsOf(tester);

    final Finder signOut = find.widgetWithText(
      LimpidButton,
      strings.actionSignOut,
    );
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();

    final Finder erase = find.widgetWithText(
      LimpidButton,
      strings.settingsEraseLocalDataConfirm,
    );
    await tester.tap(erase);
    await tester.pumpAndSettle();

    expect(await manuscripts.listProjects(), isEmpty);
    expect(auth.signOutCalls, 1);
  });

  testWidgets(
    'la suppression du compte efface les données locales après le serveur',
    (tester) async {
      useSurface(tester);
      final List<String> calls = <String>[];
      final FakeGdprRepository gdpr = FakeGdprRepository()
        ..onDeletion = () => calls.add('server');
      final FakeAuthRepository auth = FakeAuthRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gdprRepositoryProvider.overrideWithValue(gdpr),
            manuscriptRepositoryProvider.overrideWithValue(
              FakeManuscriptRepository(),
            ),
            authRepositoryProvider.overrideWithValue(auth),
            localDataEraserProvider.overrideWithValue(() async {
              calls.add('erase');
            }),
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

      expect(calls, <String>['server', 'erase']);
      expect(gdpr.deletionCalls, 1);
    },
  );
}
