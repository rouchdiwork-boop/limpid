import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

void main() {
  group('Project', () {
    test('is not public by default', () {
      expect(_project().isPublic, isFalse);
    });

    test('copyWith replaces the visibility', () {
      final Project published = _project().copyWith(
        status: ManuscriptStatus.published,
        isPublic: true,
      );

      expect(published.isPublic, isTrue);
      expect(published.status, ManuscriptStatus.published);
    });

    test('copyWith keeps the visibility it is not given', () {
      final Project project = _project().copyWith(isPublic: true);

      expect(project.copyWith(title: 'Carnets de dune').isPublic, isTrue);
    });

    test('copyWith takes the visibility out of the showcase', () {
      final Project project = _project().copyWith(
        status: ManuscriptStatus.published,
        isPublic: true,
      );

      final Project withdrawn = project.copyWith(isPublic: false);

      expect(withdrawn.isPublic, isFalse);
      expect(withdrawn.status, ManuscriptStatus.published);
    });

    test('takes the visibility into account in the equality', () {
      final Project project = _project();

      expect(project.copyWith(isPublic: true), isNot(project));
      expect(
        project.copyWith(isPublic: true),
        project.copyWith(isPublic: true),
      );
    });

    test('takes the visibility into account in the hash', () {
      expect(
        _project().copyWith(isPublic: true).hashCode,
        isNot(_project().hashCode),
      );
    });
  });
}

/// Builds a project the tests read.
Project _project({String title = 'Les Heures de Cendre'}) => Project(
  id: const ProjectId('project-1'),
  ownerId: const AuthorId('author-1'),
  title: title,
  order: OrderKey.initial,
);
