import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/auth/two_factor_proof_holder.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';
import 'package:limpid_app/src/features/webhooks/webhooks_screen.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_toolbar.dart';
import 'package:limpid_app/src/features/writing/writing_screen.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../../editor/fakes.dart' as editor;
import '../../onboarding/fakes.dart' as onboarding;
import '../../security/fakes.dart' as security;
import '../../webhooks/harness.dart' as webhooks;
import '../settings/harness.dart' as settings;
import 'fakes.dart';
import 'harness.dart';

void main() {
  setUp(TwoFactorProofHolder.reset);
  tearDown(TwoFactorProofHolder.reset);

  group("l'export d'un manuscrit", () {
    testWidgets('le refus ouvre la fenêtre et la requête est répétée', (
      tester,
    ) async {
      settings.useSurface(tester);
      final RefusingExportRepository repository = RefusingExportRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            manuscriptRepositoryProvider.overrideWithValue(
              onboarding.FakeManuscriptRepository(
                projects: <Project>[_project],
              ),
            ),
            exportRepositoryProvider.overrideWithValue(repository),
            twoFactorRepositoryProvider.overrideWithValue(_twoFactor),
          ],
          child: settings.settingsHarness(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = settings.stringsOf(tester);
      await _chooseTheManuscript(tester, strings);

      // La fenêtre du second facteur s'ouvre, et rien n'est exporté encore.
      expect(find.text(strings.twoFactorProofMissing), findsOneWidget);
      expect(repository.calls, 1);
      expect(repository.proofs, <String?>[null]);

      await _giveTheCode(tester, strings);

      // La requête est répétée, et elle porte la preuve.
      expect(repository.calls, 2);
      expect(repository.proofs, <String?>[null, 'preuve-1']);
    });
  });

  group('les données personnelles', () {
    testWidgets('le refus ouvre la fenêtre et la requête est répétée', (
      tester,
    ) async {
      settings.useSurface(tester);
      final RefusingGdprRepository repository = RefusingGdprRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            manuscriptRepositoryProvider.overrideWithValue(
              onboarding.FakeManuscriptRepository(),
            ),
            gdprRepositoryProvider.overrideWithValue(repository),
            twoFactorRepositoryProvider.overrideWithValue(_twoFactor),
          ],
          child: settings.settingsHarness(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = settings.stringsOf(tester);
      await _chooseThePersonalData(tester, strings);

      expect(find.text(strings.twoFactorProofMissing), findsOneWidget);
      expect(repository.calls, 1);

      await _giveTheCode(tester, strings);

      expect(repository.calls, 2);
      expect(repository.proofs, <String?>[null, 'preuve-1']);
    });
  });

  group('la facturation', () {
    testWidgets('le refus ouvre la fenêtre et la requête est répétée', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final RefusingPlanRepository repository = RefusingPlanRepository();

      await tester.pumpWidget(
        actionHarness(
          home: const BillingActionScreen(),
          plans: repository,
          twoFactor: _twoFactor,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = _stringsOf(
        tester,
        find.byType(BillingActionScreen),
      );

      await tester.tap(find.text('choisir'));
      await tester.pumpAndSettle();

      expect(find.text(strings.twoFactorProofMissing), findsOneWidget);
      expect(repository.calls, 1);

      await _giveTheCode(tester, strings);

      expect(repository.calls, 2);
      expect(repository.proofs, <String?>[null, 'preuve-1']);
    });
  });

  group('les équipes', () {
    testWidgets('le refus ouvre la fenêtre et la requête est répétée', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final RefusingTeamRepository repository = RefusingTeamRepository();

      await tester.pumpWidget(
        actionHarness(
          home: const TeamActionScreen(),
          teams: repository,
          twoFactor: _twoFactor,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = _stringsOf(
        tester,
        find.byType(TeamActionScreen),
      );

      await tester.tap(find.text('changer'));
      await tester.pumpAndSettle();

      expect(find.text(strings.twoFactorProofMissing), findsOneWidget);
      expect(repository.calls, 1);

      await _giveTheCode(tester, strings);

      expect(repository.calls, 2);
      expect(repository.proofs, <String?>[null, 'preuve-1']);
    });
  });

  group('les webhooks', () {
    testWidgets('le refus ouvre la fenêtre et la requête est répétée', (
      tester,
    ) async {
      webhooks.useSurface(tester, const Size(900, 1400));
      final RefusingWebhookRepository repository = RefusingWebhookRepository();

      await tester.pumpWidget(
        webhooksActionHarness(repository: repository, twoFactor: _twoFactor),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = webhooks.stringsOf(
        tester,
        find.byType(WebhooksScreen),
      );

      await _createTheEndpoint(tester, strings);

      expect(find.text(strings.twoFactorProofMissing), findsOneWidget);
      expect(repository.calls, 1);

      await _giveTheCode(tester, strings);

      expect(repository.calls, 2);
      expect(repository.proofs, <String?>[null, 'preuve-1']);
    });
  });

  group('la publication', () {
    testWidgets('le refus ouvre la fenêtre et la requête est répétée', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final RefusingKdpRepository repository = RefusingKdpRepository();

      await tester.pumpWidget(
        actionHarness(
          home: const KdpActionScreen(),
          kdp: repository,
          twoFactor: _twoFactor,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = _stringsOf(
        tester,
        find.byType(KdpActionScreen),
      );

      await tester.tap(find.text('déposer'));
      await tester.pumpAndSettle();

      expect(find.text(strings.twoFactorProofMissing), findsOneWidget);
      expect(repository.calls, 1);

      await _giveTheCode(tester, strings);

      expect(repository.calls, 2);
      expect(repository.proofs, <String?>[null, 'preuve-1']);
    });
  });

  group('l’assistant', () {
    testWidgets('le refus ouvre la fenêtre et la requête est répétée', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final RefusingAiRepository repository = RefusingAiRepository();

      await tester.pumpWidget(
        actionHarness(
          home: const WritingScreen(projectId: 'projet-1'),
          ai: repository,
          twoFactor: _twoFactor,
          manuscripts: editor.FakeManuscriptRepository(
            chapters: <Chapter>[
              editor.fakeChapter(id: 'chapitre-1', title: 'Le sel'),
            ],
            scenes: <String, List<Scene>>{
              'chapitre-1': <Scene>[
                editor.fakeScene(
                  id: 'scene-1',
                  chapterId: 'chapitre-1',
                  title: 'La plage à marée basse',
                  wordCount: 3,
                ),
              ],
            },
            documents: <String, CrdtDocument>{
              'scene-1-document': editor.fakeDocument(
                documentId: 'scene-1-document',
                text: 'Bonjour le monde',
              ),
            },
          ),
        ),
      );
      await _settle(tester);

      final AppLocalizations strings = _stringsOf(
        tester,
        find.byType(WritingScreen),
      );

      await tester.tap(
        find.descendant(
          of: find.byType(WritingToolbar),
          matching: find.text(strings.editorAiTitle),
        ),
      );
      await _settle(tester);

      await tester.enterText(find.byType(TextField), 'Continue la scène');
      await tester.tap(find.widgetWithText(LimpidButton, strings.editorAiSend));
      await _settle(tester);

      expect(find.text(strings.twoFactorProofMissing), findsOneWidget);
      expect(repository.calls, 1);

      await _giveTheCode(tester, strings);

      expect(repository.calls, 2);
      expect(repository.proofs, <String?>[null, 'preuve-1']);
    });
  });

  group('les refus qui ne sont pas le second facteur', () {
    testWidgets('n’ouvrent pas la fenêtre du code', (tester) async {
      settings.useSurface(tester);
      final RefusingExportRepository repository = RefusingExportRepository()
        ..refusal = const ApiNotFoundException('Ce livre n’existe pas.');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            manuscriptRepositoryProvider.overrideWithValue(
              onboarding.FakeManuscriptRepository(
                projects: <Project>[_project],
              ),
            ),
            exportRepositoryProvider.overrideWithValue(repository),
            twoFactorRepositoryProvider.overrideWithValue(_twoFactor),
          ],
          child: settings.settingsHarness(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = settings.stringsOf(tester);
      await _chooseTheManuscript(tester, strings);

      // La fenêtre ne s'ouvre pas, et l'action n'est pas répétée.
      expect(find.text(strings.twoFactorProofMissing), findsNothing);
      expect(repository.calls, 1);
    });
  });

  group("l'annulation de la fenêtre", () {
    testWidgets('laisse l’erreur et ne repart rien', (tester) async {
      settings.useSurface(tester);
      final RefusingExportRepository repository = RefusingExportRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            manuscriptRepositoryProvider.overrideWithValue(
              onboarding.FakeManuscriptRepository(
                projects: <Project>[_project],
              ),
            ),
            exportRepositoryProvider.overrideWithValue(repository),
            twoFactorRepositoryProvider.overrideWithValue(_twoFactor),
          ],
          child: settings.settingsHarness(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = settings.stringsOf(tester);
      await _chooseTheManuscript(tester, strings);

      expect(find.text(strings.twoFactorProofMissing), findsOneWidget);

      await tester.tap(find.text(strings.actionCancel));
      await tester.pumpAndSettle();

      // L'auteur a renoncé : rien ne repart, et l'erreur lui est montrée.
      expect(repository.calls, 1);
      expect(find.text(strings.exportFailed), findsOneWidget);
    });
  });

  group('une action locale', () {
    testWidgets('n’ouvre aucune fenêtre', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      final FailingLocalManuscriptRepository repository =
          FailingLocalManuscriptRepository();

      await tester.pumpWidget(
        actionHarness(
          home: const LocalActionScreen(),
          manuscripts: repository,
          twoFactor: _twoFactor,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = _stringsOf(
        tester,
        find.byType(LocalActionScreen),
      );

      await tester.tap(find.text('écrire'));
      await tester.pumpAndSettle();

      // L'écriture est locale : elle n'ouvre pas la fenêtre du code, même
      // quand l'échec ressemble à un refus du second facteur.
      expect(find.text(strings.twoFactorProofMissing), findsNothing);
      expect(repository.writes, 1);
    });
  });
}

/// The manuscript the author owns.
const Project _project = Project(
  id: ProjectId('project-1'),
  ownerId: AuthorId('auteur-1'),
  title: 'Les Heures de Cendre',
  synopsis: 'Un livre sur le sel et la marée.',
  status: ManuscriptStatus.draft,
  order: OrderKey.initial,
);

/// The second factor of an account that activated it.
final security.FakeTwoFactorRepository _twoFactor =
    security.FakeTwoFactorRepository(state: security.fakeTwoFactorOn);

/// The strings of the screen found by [finder].
AppLocalizations _stringsOf(WidgetTester tester, Finder finder) =>
    AppLocalizations.of(tester.element(finder));

/// Lets the author choose the manuscript to export.
Future<void> _chooseTheManuscript(
  WidgetTester tester,
  AppLocalizations strings,
) async {
  final Finder export = find.text(strings.settingsExportPersonalData);
  await tester.scrollUntilVisible(
    export,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(export);
  await tester.pumpAndSettle();

  await tester.tap(
    find.descendant(
      of: find.byType(LimpidDialog),
      matching: find.text(_project.title),
    ),
  );
  await tester.pumpAndSettle();
}

/// Lets the author choose the personal data of the account.
Future<void> _chooseThePersonalData(
  WidgetTester tester,
  AppLocalizations strings,
) async {
  final Finder export = find.text(strings.settingsExportPersonalData);
  await tester.scrollUntilVisible(
    export,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(export);
  await tester.pumpAndSettle();

  await tester.tap(
    find.descendant(
      of: find.byType(LimpidDialog),
      matching: find.text(strings.settingsExportPersonalData),
    ),
  );
  await tester.pumpAndSettle();
}

/// Lets the author create a point of reception.
Future<void> _createTheEndpoint(
  WidgetTester tester,
  AppLocalizations strings,
) async {
  await tester.tap(find.widgetWithText(LimpidButton, strings.webhooksCreate));
  await _pump(tester);

  await tester.enterText(
    find.byType(LimpidTextField),
    'https://exemple.test/limpid',
  );
  await _pump(tester);
  await tester.tap(find.text('Projet publié'));
  await _pump(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(LimpidDialog),
      matching: find.widgetWithText(LimpidButton, strings.actionCreate),
    ),
  );
  await _pump(tester);
}

/// Gives the code the author types in the window of the second factor.
Future<void> _giveTheCode(WidgetTester tester, AppLocalizations strings) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(LimpidDialog),
      matching: find.byType(LimpidTextField),
    ),
    '123456',
  );
  await tester.tap(find.text(strings.twoFactorVerify));
  await _pump(tester);
}

/// Flushes the microtasks and the frames the screen needs.
Future<void> _settle(WidgetTester tester) async {
  for (int frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Lets the screen settle, without waiting for the endless animations.
///
/// A screen that shows a spinner never settles: the test advances the
/// frames itself.
Future<void> _pump(WidgetTester tester) async {
  for (int frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
