import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/projects/project_metrics.dart';
import 'package:limpid_app/src/features/projects/project_summary.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_core/limpid_core.dart';

import 'fakes.dart';

void main() {
  /// The day the tests read.
  final DateTime today = DateTime.utc(2026, 10, 25);

  /// The day before.
  final DateTime yesterday = DateTime.utc(2026, 10, 24);

  ProviderContainer buildContainer({
    FakeManuscriptRepository? manuscripts,
    FakePreferencesRepository? preferences,
  }) {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        manuscriptRepositoryProvider.overrideWithValue(
          manuscripts ?? FakeManuscriptRepository(),
        ),
        preferencesRepositoryProvider.overrideWithValue(
          preferences ?? FakePreferencesRepository(),
        ),
        todayProvider.overrideWithValue(today),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'the figures of a project come from its chapters and its scenes',
    () async {
      final FakeManuscriptRepository manuscripts = FakeManuscriptRepository(
        projects: <Project>[
          fakeProject(
            id: 'heures',
            title: 'Les Heures de Cendre',
            status: ManuscriptStatus.writing,
            chapterIds: <String>['c1', 'c2'],
          ),
        ],
        chapters: <String, List<Chapter>>{
          'heures': <Chapter>[
            fakeChapter(
              id: 'c1',
              targetWordCount: 1000,
              sceneIds: <String>['s1'],
            ),
            fakeChapter(
              id: 'c2',
              targetWordCount: 2000,
              sceneIds: <String>['s2'],
            ),
          ],
        },
        scenes: <String, List<Scene>>{
          'c1': <Scene>[fakeScene(id: 's1', chapterId: 'c1', wordCount: 120)],
          'c2': <Scene>[
            fakeScene(
              id: 's2',
              chapterId: 'c2',
              wordCount: 330,
              updatedAt: today,
            ),
          ],
        },
      );

      final ProviderContainer container = buildContainer(
        manuscripts: manuscripts,
      );
      final LibrarySnapshot snapshot = await container.read(
        libraryProvider.future,
      );

      expect(snapshot.projects, hasLength(1));
      final ProjectSummary summary = snapshot.projects.first;
      expect(summary.title, 'Les Heures de Cendre');
      expect(summary.wordCount, 450);
      expect(summary.chapterCount, 2);
      expect(summary.sceneCount, 2);
      expect(summary.targetWordCount, 3000);
      expect(summary.status, ManuscriptStatus.writing);
    },
  );

  test(
    'the goal and the streak come from the preferences of the author',
    () async {
      final ProviderContainer container = buildContainer(
        preferences: FakePreferencesRepository(goal: 900, streak: 7),
      );

      expect(await container.read(dailyGoalProvider.future), 900);
      expect(await container.read(streakProvider.future), 7);
    },
  );

  test('the words written today come from the scenes written today', () async {
    final FakeManuscriptRepository manuscripts = FakeManuscriptRepository(
      projects: <Project>[
        fakeProject(
          id: 'heures',
          title: 'Les Heures de Cendre',
          chapterIds: <String>['c1', 'c2'],
        ),
      ],
      chapters: <String, List<Chapter>>{
        'heures': <Chapter>[
          fakeChapter(id: 'c1', sceneIds: <String>['s1']),
          fakeChapter(id: 'c2', sceneIds: <String>['s2']),
        ],
      },
      scenes: <String, List<Scene>>{
        'c1': <Scene>[
          fakeScene(
            id: 's1',
            chapterId: 'c1',
            wordCount: 100,
            updatedAt: today,
          ),
        ],
        'c2': <Scene>[
          fakeScene(
            id: 's2',
            chapterId: 'c2',
            wordCount: 250,
            updatedAt: yesterday,
          ),
        ],
      },
    );

    final ProviderContainer container = buildContainer(
      manuscripts: manuscripts,
    );
    await container.read(libraryProvider.future);

    expect(container.read(wordsWrittenTodayProvider), 100);
  });

  test('the current project is the one that is being written', () async {
    final FakeManuscriptRepository manuscripts = FakeManuscriptRepository(
      projects: <Project>[
        fakeProject(id: 'a', title: 'Carnets de dune'),
        fakeProject(
          id: 'b',
          title: 'Les Machines de sieste',
          status: ManuscriptStatus.writing,
        ),
      ],
    );

    final ProviderContainer container = buildContainer(
      manuscripts: manuscripts,
    );
    await container.read(libraryProvider.future);

    expect(
      container.read(currentProjectProvider)?.title,
      'Les Machines de sieste',
    );
  });

  test('the library fails when the repository fails', () async {
    final FakeManuscriptRepository manuscripts = FakeManuscriptRepository()
      ..error = StateError('the database is closed');

    final ProviderContainer container = buildContainer(
      manuscripts: manuscripts,
    );

    await expectLater(
      container.read(libraryProvider.future),
      throwsA(isA<StateError>()),
    );
  });
}
