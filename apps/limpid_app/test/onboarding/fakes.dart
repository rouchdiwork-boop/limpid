import 'dart:async';
import 'dart:convert';

import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';

import '../support/hierarchy_stub.dart';

/// A [ManuscriptRepository] that records what the interface asks it to do.
///
/// The fake is shared by the onboarding and the settings tests: it keeps the
/// projects it is given and the ones the interface creates.
final class FakeManuscriptRepository extends StubHierarchyRepository
    implements ManuscriptRepository {
  /// Creates the fake with the projects the author already owns.
  FakeManuscriptRepository({List<Project> projects = const <Project>[]})
    : _projects = List<Project>.of(projects);

  final List<Project> _projects;

  /// The projects the interface created, in the order of the calls.
  final List<({String title, String synopsis})> createdProjects =
      <({String title, String synopsis})>[];

  @override
  Future<List<Project>> listProjects() async =>
      List<Project>.unmodifiable(_projects);

  @override
  Future<Project?> findProject(String projectId) async {
    for (final Project project in _projects) {
      if (project.id.value == projectId) {
        return project;
      }
    }
    return null;
  }

  @override
  Future<Project> createProject({
    required String title,
    String synopsis = '',
  }) async {
    createdProjects.add((title: title, synopsis: synopsis));
    final Project project = Project(
      id: ProjectId('project-${createdProjects.length}'),
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
      const <Chapter>[];

  @override
  Future<Chapter> saveChapter(Chapter chapter) async => chapter;

  @override
  Future<List<Scene>> listScenes(String chapterId) async => const <Scene>[];

  @override
  Future<Scene> saveScene(Scene scene) async => scene;

  @override
  Future<CrdtDocument> loadDocument(String documentId) async =>
      CrdtDocument.empty(DocumentId(documentId));

  @override
  Future<void> applyOperations(List<SyncOp> operations) async {}
}

/// A [SyncRepository] the test drives by hand.
///
/// The fake publishes the status it is given and counts the
/// synchronisations the interface asks for.
final class FakeSyncRepository implements PendingChangesSyncRepository {
  /// Creates the fake with an initial status.
  FakeSyncRepository({
    SyncStatus initialStatus = SyncStatus.synced,
    this.pendingCount = 0,
  }) : currentStatus = initialStatus;

  /// The status the fake publishes.
  SyncStatus currentStatus;

  @override
  int pendingCount;

  final StreamController<SyncStatus> _controller =
      StreamController<SyncStatus>.broadcast();

  /// The number of times the interface asked for a synchronisation.
  int synchronizeCalls = 0;

  @override
  SyncStatus get status => currentStatus;

  /// Publishes a new status, as the real repository would.
  void emit(SyncStatus status) {
    currentStatus = status;
    _controller.add(status);
  }

  /// Changes the number of waiting modifications.
  void setPendingCount(int count) {
    pendingCount = count;
  }

  @override
  Stream<SyncStatus> watch() async* {
    yield currentStatus;
    yield* _controller.stream;
  }

  @override
  Future<void> synchronize() async {
    synchronizeCalls++;
  }

  /// Closes the stream of the fake.
  Future<void> close() => _controller.close();
}

/// An [ExportRepository] the test drives by hand.
final class FakeExportRepository implements ExportRepository {
  /// The exports the interface asked for, in the order of the calls.
  final List<({String projectId, ExportFormat format})> exports =
      <({String projectId, ExportFormat format})>[];

  /// The file the fake produces.
  ExportArtefact artefact = ExportArtefact(
    fileName: 'livre.md',
    mimeType: 'text/markdown',
    bytes: utf8.encode('# Livre\n'),
  );

  /// The error the fake throws, `null` when it succeeds.
  Object? error;

  @override
  Future<ExportArtefact> export({
    required String projectId,
    required ExportFormat format,
  }) async {
    exports.add((projectId: projectId, format: format));
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
    return artefact;
  }
}

/// An [AuthRepository] that records the sign out of the author.
final class FakeAuthRepository implements AuthRepository {
  /// The number of times the interface signed the author out.
  int signOutCalls = 0;

  @override
  Stream<AuthSession?> watchSession() => Stream<AuthSession?>.value(null);

  @override
  Future<void> sendMagicLink(String email, {String? authorName}) async {}

  @override
  Future<void> signInWithPassword(String email, String password) async {}

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}
