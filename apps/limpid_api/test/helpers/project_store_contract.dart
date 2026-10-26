import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

import 'store_fixture.dart';

/// Runs the contract of [ProjectStore].
///
/// The same scenarios run against the in-memory store and against the SQLite
/// one: the equality of the two runs is the proof that the development
/// database behaves like the reference implementation.
void runProjectStoreContract({
  required String name,
  required Future<StoreFixture> Function() build,
}) {
  group('contrat des dépôts — $name', () {
    late StoreFixture fixture;

    setUp(() async {
      fixture = await build();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    group('projets', () {
      test('crée un projet et le renvoie', () async {
        final ProjectRecord project = await createProject(fixture);

        expect(project.id, isNotEmpty);
        expect(project.ownerId, 'user-1');
        expect(project.title, 'Titre');
        expect(project.synopsis, 'Un synopsis.');
        expect(project.status, ManuscriptStatus.draft);
        expect(project.language, 'fr-FR');
        expect(project.orderKey, '5');
        expect(project.isPublic, isFalse);
        expect(project.isDeleted, isFalse);
        expect(project.createdAt, project.updatedAt);
      });

      test('attribue un identifiant unique à chaque projet', () async {
        final ProjectRecord first = await createProject(fixture);
        final ProjectRecord second = await createProject(fixture);

        expect(first.id, isNot(second.id));
      });

      test('réserve le projet à son propriétaire', () async {
        final ProjectRecord project = await createProject(fixture);

        final ProjectAccess? access = await fixture.projects.access(
          projectId: project.id,
          userId: 'user-1',
        );

        expect(access, isNotNull);
        expect(access!.role, ProjectRole.owner);
        expect(access.project.id, project.id);
        expect(access.project.title, project.title);
      });

      test('cache un projet des autres comptes', () async {
        final ProjectRecord project = await createProject(fixture);

        final ProjectAccess? access = await fixture.projects.access(
          projectId: project.id,
          userId: 'user-2',
        );

        expect(access, isNull);
      });

      test('donne le rôle du collaborateur', () async {
        final ProjectRecord project = await createProject(fixture);
        await fixture.addMember(
          projectId: project.id,
          userId: 'user-2',
          role: ProjectRole.betaReader,
        );

        final ProjectAccess? access = await fixture.projects.access(
          projectId: project.id,
          userId: 'user-2',
        );

        expect(access, isNotNull);
        expect(access!.role, ProjectRole.betaReader);
      });

      test('masque un projet supprimé', () async {
        final ProjectRecord project = await createProject(fixture);

        await fixture.projects.softDelete(projectId: project.id);

        expect(
          await fixture.projects.access(
            projectId: project.id,
            userId: 'user-1',
          ),
          isNull,
        );
      });

      test('liste les projets du propriétaire', () async {
        await createProject(fixture, title: 'Premier');
        await createProject(fixture, title: 'Second');
        await createProject(fixture, ownerId: 'user-2', title: 'Autre compte');

        final ProjectPage page = await fixture.projects.list(
          userId: 'user-1',
          limit: 10,
          cursor: null,
        );

        expect(page.items, hasLength(2));
        expect(page.total, 2);
        expect(page.nextCursor, isNull);
      });

      test('liste les projets partagés avec le compte', () async {
        final ProjectRecord shared = await createProject(
          fixture,
          ownerId: 'user-2',
        );
        await fixture.addMember(
          projectId: shared.id,
          userId: 'user-1',
          role: ProjectRole.coAuthor,
        );

        final ProjectPage page = await fixture.projects.list(
          userId: 'user-1',
          limit: 10,
          cursor: null,
        );

        expect(page.items.map((ProjectRecord p) => p.id), <String>[shared.id]);
        expect(page.total, 1);
      });

      test('exclut les projets supprimés de la liste', () async {
        final ProjectRecord project = await createProject(fixture);
        await fixture.projects.softDelete(projectId: project.id);

        final ProjectPage page = await fixture.projects.list(
          userId: 'user-1',
          limit: 10,
          cursor: null,
        );

        expect(page.items, isEmpty);
        expect(page.total, 0);
      });

      test('trie par date décroissante puis identifiant croissant', () async {
        for (var index = 0; index < 3; index++) {
          await createProject(fixture, title: 'Projet $index');
        }

        final ProjectPage page = await fixture.projects.list(
          userId: 'user-1',
          limit: 10,
          cursor: null,
        );

        expect(page.items, hasLength(3));
        for (var index = 1; index < page.items.length; index++) {
          final ProjectRecord previous = page.items[index - 1];
          final ProjectRecord current = page.items[index];
          final int byDate = previous.updatedAt.compareTo(current.updatedAt);
          expect(byDate, greaterThanOrEqualTo(0));
          if (byDate == 0) {
            expect(previous.id.compareTo(current.id), lessThan(0));
          }
        }
      });

      test('pagine sans recouvrement', () async {
        for (var index = 0; index < 5; index++) {
          await createProject(fixture, title: 'Projet $index');
        }

        final ProjectPage first = await fixture.projects.list(
          userId: 'user-1',
          limit: 2,
          cursor: null,
        );
        expect(first.items, hasLength(2));
        expect(first.total, 5);
        expect(first.nextCursor, isNotNull);

        final ProjectPage second = await fixture.projects.list(
          userId: 'user-1',
          limit: 2,
          cursor: first.nextCursor,
        );
        expect(second.items, hasLength(2));
        expect(second.nextCursor, isNotNull);

        final ProjectPage third = await fixture.projects.list(
          userId: 'user-1',
          limit: 2,
          cursor: second.nextCursor,
        );
        expect(third.items, hasLength(1));
        expect(third.nextCursor, isNull);

        final Set<String> ids = <String>{
          ...first.items.map((ProjectRecord p) => p.id),
          ...second.items.map((ProjectRecord p) => p.id),
          ...third.items.map((ProjectRecord p) => p.id),
        };
        expect(ids, hasLength(5));
      });

      test('met à jour un projet', () async {
        final ProjectRecord project = await createProject(fixture);

        final ProjectRecord updated = await fixture.projects.update(
          project.copyWith(
            title: 'Titre corrigé',
            status: ManuscriptStatus.writing,
            isPublic: true,
          ),
        );

        expect(updated.title, 'Titre corrigé');
        expect(updated.status, ManuscriptStatus.writing);
        expect(updated.isPublic, isTrue);
        expect(updated.updatedAt.isBefore(project.updatedAt), isFalse);
        expect(updated.createdAt, project.createdAt);
      });

      test('refuse de mettre à jour un projet inconnu', () async {
        final ProjectRecord ghost = ProjectRecord(
          id: 'projet-inconnu',
          ownerId: 'user-1',
          title: 'Fantôme',
          synopsis: '',
          status: ManuscriptStatus.draft,
          language: 'fr-FR',
          orderKey: '5',
          isPublic: false,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        );

        expect(fixture.projects.update(ghost), throwsA(isA<StateError>()));
      });

      test('supprime deux fois sans échouer', () async {
        final ProjectRecord project = await createProject(fixture);

        await fixture.projects.softDelete(projectId: project.id);
        await fixture.projects.softDelete(projectId: project.id);

        expect(
          await fixture.projects.access(
            projectId: project.id,
            userId: 'user-1',
          ),
          isNull,
        );
      });

      test('ignore la suppression d\'un projet inconnu', () async {
        await expectLater(
          fixture.projects.softDelete(projectId: 'projet-inconnu'),
          completes,
        );
      });

      test(
        'ne montre un projet public que s\'il est publié et public',
        () async {
          final ProjectRecord project = await createProject(fixture);

          expect(
            await fixture.projects.findPublic(projectId: project.id),
            isNull,
            reason: 'un projet en brouillon n\'est pas public',
          );

          final ProjectRecord published = await fixture.projects.update(
            project.copyWith(status: ManuscriptStatus.published),
          );
          expect(
            await fixture.projects.findPublic(projectId: project.id),
            isNull,
            reason: 'un projet publié mais privé n\'est pas public',
          );

          final ProjectRecord open = await fixture.projects.update(
            published.copyWith(isPublic: true),
          );
          expect(
            (await fixture.projects.findPublic(projectId: project.id))?.id,
            open.id,
          );

          await fixture.projects.softDelete(projectId: project.id);
          expect(
            await fixture.projects.findPublic(projectId: project.id),
            isNull,
            reason: 'un projet supprimé n\'est plus public',
          );
        },
      );

      test('ne trouve pas un projet inconnu', () async {
        expect(
          await fixture.projects.findPublic(projectId: 'projet-inconnu'),
          isNull,
        );
      });
    });
  });
}
