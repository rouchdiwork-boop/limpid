import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';

/// The author stamping the operations built by the fakes.
const AuthorId kFakeAuthor = AuthorId('fake-author');

/// A [PublicationRepository] the test drives by hand.
///
/// The fake holds the page the repository must serve: the showcase of the
/// server, or the local manuscript.
final class FakePublicationPageRepository implements PublicationRepository {
  /// Creates a repository serving [publication].
  FakePublicationPageRepository({this.publication});

  /// The page the repository serves.
  Publication? publication;

  /// The error every read throws when it is set.
  Object? error;

  /// The number of times the page was read.
  int calls = 0;

  @override
  Future<Publication> load({required String projectId}) async {
    calls += 1;
    final Object? failure = error;
    if (failure != null) throw failure;
    return publication ?? UnknownBook(projectId: projectId);
  }
}

/// A [ManuscriptRepository] the test drives by hand.
///
/// The fake holds the projects, the chapters, the scenes and the documents
/// the test gives it: the public page is computed from them, exactly as it
/// is computed from the local database.
final class FakePublicationRepository implements ManuscriptRepository {
  /// Creates the repository with the manuscripts the author already owns.
  FakePublicationRepository({
    List<Project> projects = const <Project>[],
    Map<String, List<Chapter>> chapters = const <String, List<Chapter>>{},
    Map<String, List<Scene>> scenes = const <String, List<Scene>>{},
    Map<String, CrdtDocument> documents = const <String, CrdtDocument>{},
  }) : _projects = List<Project>.of(projects),
       _chapters = <String, List<Chapter>>{
         for (final MapEntry<String, List<Chapter>> entry in chapters.entries)
           entry.key: List<Chapter>.of(entry.value),
       },
       _scenes = <String, List<Scene>>{
         for (final MapEntry<String, List<Scene>> entry in scenes.entries)
           entry.key: List<Scene>.of(entry.value),
       },
       _documents = Map<String, CrdtDocument>.of(documents);

  final List<Project> _projects;
  final Map<String, List<Chapter>> _chapters;
  final Map<String, List<Scene>> _scenes;
  final Map<String, CrdtDocument> _documents;

  /// The error every read throws when it is set.
  Object? error;

  /// The number of times the documents were read.
  int loadDocumentCalls = 0;

  @override
  Future<List<Project>> listProjects() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<Project>.unmodifiable(_projects);
  }

  @override
  Future<Project?> findProject(String projectId) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    for (final Project project in _projects) {
      if (project.id.value == projectId) return project;
    }
    return null;
  }

  @override
  Future<Project> createProject({
    required String title,
    String synopsis = '',
  }) async {
    final Project project = Project(
      id: ProjectId('project-${_projects.length + 1}'),
      ownerId: kFakeAuthor,
      title: title,
      synopsis: synopsis,
      status: ManuscriptStatus.draft,
      order: OrderKey.initial,
    );
    _projects.add(project);
    return project;
  }

  @override
  Future<Project> saveProject(Project project) async {
    _projects.removeWhere((Project saved) => saved.id == project.id);
    _projects.add(project);
    return project;
  }

  @override
  Future<void> deleteProject(String projectId) async {
    _projects.removeWhere((Project project) => project.id.value == projectId);
  }

  @override
  Future<List<Chapter>> listChapters(String projectId) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<Chapter>.unmodifiable(
      _chapters[projectId] ?? const <Chapter>[],
    );
  }

  @override
  Future<Chapter> saveChapter(Chapter chapter) async => chapter;

  @override
  Future<List<Scene>> listScenes(String chapterId) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<Scene>.unmodifiable(_scenes[chapterId] ?? const <Scene>[]);
  }

  @override
  Future<Scene> saveScene(Scene scene) async => scene;

  @override
  Future<CrdtDocument> loadDocument(String documentId) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    loadDocumentCalls++;
    return _documents[documentId] ?? CrdtDocument.empty(DocumentId(documentId));
  }

  @override
  Future<void> applyOperations(List<SyncOp> operations) async {}
}

/// A project for the tests.
Project fakePublicationProject({
  required String id,
  required String title,
  String synopsis = '',
  ManuscriptStatus status = ManuscriptStatus.published,
}) {
  return Project(
    id: ProjectId(id),
    ownerId: kFakeAuthor,
    title: title,
    synopsis: synopsis,
    status: status,
    order: OrderKey.initial,
  );
}

/// A chapter for the tests.
Chapter fakePublicationChapter({
  required String id,
  required String title,
  String synopsis = '',
  List<String> sceneIds = const <String>[],
}) {
  return Chapter(
    id: ChapterId(id),
    title: title,
    synopsis: synopsis,
    order: OrderKey.initial,
    sceneIds: sceneIds.map<SceneId>(SceneId.new).toList(growable: false),
  );
}

/// A scene for the tests.
Scene fakePublicationScene({
  required String id,
  required String chapterId,
  required String title,
  int wordCount = 0,
}) {
  return Scene(
    id: SceneId(id),
    chapterId: ChapterId(chapterId),
    documentId: DocumentId('document-$id'),
    title: title,
    order: OrderKey.initial,
    wordCount: wordCount,
  );
}

/// Builds the document of a scene: one paragraph per given text.
///
/// The paragraphs are inserted in the given order, so that the excerpt of
/// the scene is the first of them.
CrdtDocument fakePublicationDocument({
  required String documentId,
  required List<String> paragraphs,
}) {
  final DocumentId id = DocumentId(documentId);
  CrdtDocument document = CrdtDocument.empty(id);
  OrderKey order = OrderKey.initial;

  for (int index = 0; index < paragraphs.length; index++) {
    order = OrderKey.between(order, null);
    document = document.apply(
      InsertBlockOp(
        doc: id,
        lamport: index + 1,
        author: kFakeAuthor,
        blockId: BlockId('$documentId-block-$index'),
        parent: null,
        order: order,
        type: BlockType.paragraph,
        content: TextContent(paragraphs[index]),
      ),
    );
  }
  return document;
}
