import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';

import '../../support/hierarchy_stub.dart';

/// A [ManuscriptRepository] the test drives by hand.
///
/// The fake holds the projects, the chapters and the scenes the test gives
/// it: the figures of the interface are computed from them, exactly as they
/// are computed from the local database.
final class FakeManuscriptRepository extends StubHierarchyRepository
    implements ManuscriptRepository {
  /// Creates the repository with the manuscripts the author already owns.
  FakeManuscriptRepository({
    List<Project> projects = const <Project>[],
    Map<String, List<Chapter>> chapters = const <String, List<Chapter>>{},
    Map<String, List<Scene>> scenes = const <String, List<Scene>>{},
  }) : _projects = List<Project>.of(projects),
       _chapters = <String, List<Chapter>>{
         for (final MapEntry<String, List<Chapter>> entry in chapters.entries)
           entry.key: List<Chapter>.of(entry.value),
       },
       _scenes = <String, List<Scene>>{
         for (final MapEntry<String, List<Scene>> entry in scenes.entries)
           entry.key: List<Scene>.of(entry.value),
       };

  final List<Project> _projects;
  final Map<String, List<Chapter>> _chapters;
  final Map<String, List<Scene>> _scenes;

  /// The error the repository throws when the library is read.
  Object? error;

  /// Les chapitres que l'ecran a crees, dans l'ordre.
  ///
  /// Le doublure note ce que l'ecran a demande : le test prouve ainsi que
  /// le bouton « Creer » **fait** quelque chose.
  final List<Chapter> createdChapters = <Chapter>[];

  /// The number of times the library was read.
  int listProjectsCalls = 0;

  @override
  Future<Chapter> createChapter({
    required String projectId,
    String? volumeId,
    required String title,
    String synopsis = '',
  }) async {
    final Chapter chapter = Chapter(
      id: ChapterId('chapter-cree-${createdChapters.length + 1}'),
      volumeId: volumeId == null ? null : VolumeId(volumeId),
      title: title,
      order: OrderKey('${createdChapters.length + 1}'),
    );
    createdChapters.add(chapter);
    _chapters.putIfAbsent(projectId, () => <Chapter>[]).add(chapter);
    return chapter;
  }

  @override
  Future<List<Project>> listProjects() async {
    listProjectsCalls++;
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<Project>.unmodifiable(_projects);
  }

  @override
  Future<Project?> findProject(String projectId) async {
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
      ownerId: const AuthorId('test-author'),
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
  Future<List<Chapter>> listChapters(String projectId) async =>
      List<Chapter>.unmodifiable(_chapters[projectId] ?? const <Chapter>[]);

  @override
  Future<Chapter> saveChapter(Chapter chapter) async => chapter;

  @override
  Future<List<Scene>> listScenes(String chapterId) async =>
      List<Scene>.unmodifiable(_scenes[chapterId] ?? const <Scene>[]);

  @override
  Future<Scene> saveScene(Scene scene) async => scene;

  @override
  Future<CrdtDocument> loadDocument(String documentId) async =>
      CrdtDocument.empty(DocumentId(documentId));

  @override
  Future<void> applyOperations(List<SyncOp> operations) async {}
}

/// A [PreferencesRepository] the test drives by hand.
final class FakePreferencesRepository implements PreferencesRepository {
  /// Creates the repository with the figures it starts from.
  FakePreferencesRepository({this.goal = 1500, this.streak = 0});

  /// The number of words the author aims to write every day.
  int goal;

  /// The number of consecutive days on which the author wrote.
  int streak;

  @override
  Future<int> dailyGoal() async => goal;

  @override
  Future<void> setDailyGoal(int? words) async {
    if (words == null || words <= 0) return;
    goal = words;
  }

  @override
  Future<int> writingStreak() async => streak;
}

/// A project for the tests.
Project fakeProject({
  required String id,
  required String title,
  ManuscriptStatus status = ManuscriptStatus.draft,
  List<String> chapterIds = const <String>[],
  DateTime? updatedAt,
}) {
  return Project(
    id: ProjectId(id),
    ownerId: const AuthorId('test-author'),
    title: title,
    synopsis: '',
    status: status,
    order: OrderKey.initial,
    chapterIds: chapterIds
        .map<ChapterId>(ChapterId.new)
        .toList(growable: false),
    updatedAt: updatedAt,
  );
}

/// A chapter for the tests.
Chapter fakeChapter({
  required String id,
  int targetWordCount = 0,
  List<String> sceneIds = const <String>[],
}) {
  return Chapter(
    id: ChapterId(id),
    title: 'Chapter $id',
    order: OrderKey.initial,
    sceneIds: sceneIds.map<SceneId>(SceneId.new).toList(growable: false),
    targetWordCount: targetWordCount,
  );
}

/// A scene for the tests.
Scene fakeScene({
  required String id,
  required String chapterId,
  int wordCount = 0,
  int targetWordCount = 0,
  DateTime? updatedAt,
}) {
  return Scene(
    id: SceneId(id),
    chapterId: ChapterId(chapterId),
    documentId: DocumentId('document-$id'),
    title: 'Scene $id',
    order: OrderKey.initial,
    wordCount: wordCount,
    targetWordCount: targetWordCount,
    updatedAt: updatedAt,
  );
}
