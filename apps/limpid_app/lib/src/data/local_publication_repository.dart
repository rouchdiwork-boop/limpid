import 'package:limpid_app/src/data/published_book_reader.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';

/// The public page of a book, served by the local database.
///
/// The repository is the **local first** answer: the page of a book opens
/// from the manuscript of the device, even without a network. The manuscript
/// decides whether the page exists — only a published book has one — and
/// every scene is reduced to its excerpt: the public page never carries the
/// whole text of a manuscript.
final class LocalPublicationRepository implements PublicationRepository {
  /// Creates a repository on top of [manuscript].
  const LocalPublicationRepository({required this.manuscript});

  /// The manuscripts of the author.
  final ManuscriptRepository manuscript;

  @override
  Future<Publication> load({required String projectId}) async {
    final Project? project = await _projectOf(projectId);
    if (project == null) {
      return UnknownBook(projectId: projectId);
    }
    if (project.status != ManuscriptStatus.published) {
      return UnpublishedBook(project: project);
    }

    final List<Chapter> chapters = await manuscript.listChapters(projectId);
    final List<PublicationChapter> published = <PublicationChapter>[];
    for (final Chapter chapter in chapters) {
      published.add(await _chapterOf(chapter));
    }

    return PublishedBook(
      project: project,
      chapters: List<PublicationChapter>.unmodifiable(published),
    );
  }

  /// The project the public page is about.
  ///
  /// A published book is public: the local database serves it to any reader,
  /// even to a reader who is not its author. The manuscript of the author is
  /// the fallback: the reader then sees that the book has no public page.
  Future<Project?> _projectOf(String projectId) async {
    final Object repository = manuscript;
    if (repository is PublishedBookReader) {
      final Project? published = await repository.findPublishedProject(
        projectId,
      );
      if (published != null) return published;
    }
    return manuscript.findProject(projectId);
  }

  /// The chapter of the public page, with the excerpt of every scene.
  Future<PublicationChapter> _chapterOf(Chapter chapter) async {
    final List<Scene> scenes = await manuscript.listScenes(chapter.id.value);
    final List<PublicationScene> excerpts = await Future.wait<PublicationScene>(
      scenes.map((Scene scene) => _sceneOf(scene)),
    );
    return PublicationChapter(
      id: chapter.id,
      title: chapter.title,
      synopsis: chapter.synopsis,
      scenes: List<PublicationScene>.unmodifiable(excerpts),
    );
  }

  /// The scene of the public page: its title, its excerpt and its length.
  Future<PublicationScene> _sceneOf(Scene scene) async {
    final CrdtDocument document = await manuscript.loadDocument(
      scene.documentId.value,
    );
    return PublicationScene(
      id: scene.id,
      title: scene.title,
      excerpt: excerptOf(document),
      wordCount: scene.wordCount,
    );
  }
}
