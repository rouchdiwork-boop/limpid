import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/project/project_screen.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../projects/fakes.dart';

void main() {
  /// Gives the test a viewport large enough for the desktop layout.
  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Builds the container of the test, with the library already loaded.
  Future<ProviderContainer> buildContainer(
    FakeManuscriptRepository manuscripts,
  ) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        manuscriptRepositoryProvider.overrideWithValue(manuscripts),
        preferencesRepositoryProvider.overrideWithValue(
          FakePreferencesRepository(),
        ),
        todayProvider.overrideWithValue(DateTime.utc(2026, 10, 25)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(libraryProvider.future);
    return container;
  }

  /// Displays the screen of a project.
  Widget harness(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: LimpidTheme.of(LimpidThemeVariant.paper),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Les textes de l'ecran sont asserts en francais : la locale est
        // posee, sinon le poste de test choisirait l'anglais.
        locale: const Locale('fr'),
        home: const ProjectScreen(projectId: 'heures'),
      ),
    );
  }

  /// Builds a project of the library.
  Project project({
    ManuscriptStatus status = ManuscriptStatus.draft,
    bool isPublic = false,
  }) {
    return Project(
      id: const ProjectId('heures'),
      ownerId: const AuthorId('test-author'),
      title: 'Les Heures de Cendre',
      synopsis: 'Une archiviste et une cloche.',
      status: status,
      isPublic: isPublic,
      order: OrderKey.initial,
    );
  }

  testWidgets('le bouton de creation ajoute un chapitre au livre', (
    tester,
  ) async {
    // Le bouton « Créer » de la carte des chapitres n'etait **branche a
    // rien** : il etait desactive, et le livre n'avait pas de chapitre.
    final FakeManuscriptRepository manuscripts = FakeManuscriptRepository(
      projects: <Project>[project()],
    );
    final ProviderContainer container = await buildContainer(manuscripts);
    useSurface(tester, const Size(1400, 1000));

    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Le premier chapitre');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer').last);
    await tester.pumpAndSettle();

    expect(manuscripts.createdChapters, hasLength(1));
    expect(manuscripts.createdChapters.single.title, 'Le premier chapitre');
  });

  testWidgets('the action asks for a confirmation before publishing', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    final FakeManuscriptRepository manuscripts = FakeManuscriptRepository(
      projects: <Project>[project()],
    );
    final ProviderContainer container = await buildContainer(manuscripts);

    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(ProjectScreen)),
    );

    // The book is not published yet: the interface says so.
    expect(find.text(strings.projectPublicationStateDraft), findsOneWidget);

    await tester.tap(
      find.widgetWithText(LimpidButton, strings.projectPublishAction),
    );
    await tester.pumpAndSettle();

    expect(find.text(strings.projectPublishConfirmTitle), findsOneWidget);
    expect(find.text(strings.projectPublishConfirmMessage), findsOneWidget);

    // Nothing is written before the author confirms.
    final Project stored = (await manuscripts.listProjects()).first;
    expect(stored.status, ManuscriptStatus.draft);
    expect(stored.isPublic, isFalse);

    await tester.tap(find.widgetWithText(LimpidButton, strings.actionCancel));
    await tester.pumpAndSettle();

    expect(find.text(strings.projectPublishConfirmTitle), findsNothing);
    final Project cancelled = (await manuscripts.listProjects()).first;
    expect(cancelled.status, ManuscriptStatus.draft);
    expect(cancelled.isPublic, isFalse);
  });

  testWidgets('publishing writes the two states and shows them', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    final FakeManuscriptRepository manuscripts = FakeManuscriptRepository(
      projects: <Project>[project()],
    );
    final ProviderContainer container = await buildContainer(manuscripts);

    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(ProjectScreen)),
    );

    await tester.tap(
      find.widgetWithText(LimpidButton, strings.projectPublishAction),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(LimpidButton, strings.projectPublishConfirmAction),
    );
    await tester.pumpAndSettle();

    final Project stored = (await manuscripts.listProjects()).first;
    expect(stored.status, ManuscriptStatus.published);
    expect(stored.isPublic, isTrue);

    // The interface shows the new state of the book.
    expect(find.text(strings.projectPublicationStateShowcase), findsOneWidget);
    expect(
      find.widgetWithText(LimpidButton, strings.projectUnpublishAction),
      findsOneWidget,
    );
  });

  testWidgets('taking the book out of the showcase keeps it published', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    final FakeManuscriptRepository manuscripts = FakeManuscriptRepository(
      projects: <Project>[
        project(status: ManuscriptStatus.published, isPublic: true),
      ],
    );
    final ProviderContainer container = await buildContainer(manuscripts);

    await tester.pumpWidget(harness(container));
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(ProjectScreen)),
    );

    expect(find.text(strings.projectPublicationStateShowcase), findsOneWidget);

    await tester.tap(
      find.widgetWithText(LimpidButton, strings.projectUnpublishAction),
    );
    await tester.pumpAndSettle();

    expect(find.text(strings.projectUnpublishConfirmTitle), findsOneWidget);

    await tester.tap(
      find.widgetWithText(LimpidButton, strings.projectUnpublishConfirmAction),
    );
    await tester.pumpAndSettle();

    final Project stored = (await manuscripts.listProjects()).first;
    expect(stored.status, ManuscriptStatus.published);
    expect(stored.isPublic, isFalse);

    // The book is published, but it left the showcase.
    expect(find.text(strings.projectPublicationStatePublished), findsOneWidget);
    expect(
      find.widgetWithText(LimpidButton, strings.projectPublishAction),
      findsOneWidget,
    );
  });
}
