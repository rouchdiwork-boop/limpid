/// Les doublures en mémoire des contrats de l'application.
///
/// Une doublure est une implémentation de contrat qui ne touche **ni au
/// disque, ni au réseau** : elle tient tout en mémoire. Le point de
/// composition s'en sert quand un service n'est pas configuré sur ce poste
/// — le mode démonstration, la base locale qui ne s'ouvre pas.
///
/// Elles vivent avec les contrats qu'elles réalisent : une doublure du
/// domaine ne connaît que le domaine.
library;

import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';

/// An in-memory [ManuscriptRepository].
///
/// It is the fallback of the composition root: when the local database cannot
/// be opened — on the web without the WebAssembly module, for instance — the
/// application still starts, and the author can still write. The manuscripts
/// are really created, they simply do not survive the closing of the
/// application, and the interface says so.
final class DemoManuscriptRepository implements ManuscriptRepository {
  /// Creates the repository.
  DemoManuscriptRepository();

  final Map<ProjectId, Project> _projects = <ProjectId, Project>{};
  final UlidGenerator _ids = UlidGenerator();
  OrderKey? _lastOrder;

  @override
  Future<List<Project>> listProjects() async {
    final List<Project> projects = _projects.values.toList(growable: false);
    projects.sort(_byMostRecent);
    return List<Project>.unmodifiable(projects);
  }

  @override
  Future<Project?> findProject(String projectId) async =>
      _projects[ProjectId(projectId)];

  @override
  Future<Project> createProject({
    required String title,
    String synopsis = '',
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final OrderKey order = OrderKey.between(_lastOrder, null);
    _lastOrder = order;
    final Project project = Project(
      id: ProjectId(_ids.generate().toString()),
      ownerId: const AuthorId('demo-author'),
      title: title,
      synopsis: synopsis,
      status: ManuscriptStatus.draft,
      order: order,
      createdAt: now,
      updatedAt: now,
    );
    _projects[project.id] = project;
    return project;
  }

  @override
  Future<Project> saveProject(Project project) async {
    final Project saved = project.copyWith(updatedAt: DateTime.now().toUtc());
    _projects[saved.id] = saved;
    return saved;
  }

  @override
  Future<void> deleteProject(String projectId) async {
    _projects.remove(ProjectId(projectId));
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

  static int _byMostRecent(Project left, Project right) {
    final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return (right.updatedAt ?? epoch).compareTo(left.updatedAt ?? epoch);
  }
}

/// A [SyncRepository] that cannot reach the server.
///
/// It stays offline: the queue of the device is untouched and the settings
/// screen says so instead of showing a fake synchronisation.
final class OfflineSyncRepository
    implements SyncRepository, UnavailableService {
  /// Creates the repository.
  OfflineSyncRepository();

  @override
  SyncStatus get status => SyncStatus.offline;

  @override
  Stream<SyncStatus> watch() => Stream<SyncStatus>.value(SyncStatus.offline);

  @override
  Future<void> synchronize() async {
    // The server is unreachable: the contract says the queue stays intact and
    // the status stays offline.
  }
}

/// An [ExportRepository] that cannot reach the server.
///
/// The export runs on the server: when it cannot be reached, the repository
/// refuses the export instead of returning a file that was never produced.
final class UnavailableExportRepository
    implements ExportRepository, UnavailableService {
  /// Creates the repository.
  const UnavailableExportRepository();

  @override
  Future<ExportArtefact> export({
    required String projectId,
    required ExportFormat format,
  }) async {
    throw const ServiceUnavailableException();
  }
}

/// A [GdprRepository] that cannot reach the backend.
///
/// The demonstration mode has no remote service: the interface says so
/// instead of pretending that the export or the deletion happened.
final class UnavailableGdprRepository
    implements GdprRepository, UnavailableService {
  /// Creates the repository.
  const UnavailableGdprRepository();

  @override
  Future<PersonalDataExport> exportPersonalData() async =>
      throw const ServiceUnavailableException();

  @override
  Future<AccountDeletion> requestAccountDeletion() async =>
      throw const ServiceUnavailableException();
}

/// The preferences of the author, kept in the memory of the application.
/// The daily goal and the series of the writing days are the two figures the
/// dashboard needs. Until the durable implementation is wired, the goal is
/// the regular rhythm of the design system and the series is empty: the
/// interface shows the truth, never a figure it invented.
final class InMemoryPreferencesRepository implements PreferencesRepository {
  /// Creates the repository.
  InMemoryPreferencesRepository();

  /// The daily goal, kept in the memory of the application.
  int _dailyGoal = 1500;

  /// The number of consecutive days on which the author wrote.
  final int _writingStreak = 0;

  @override
  Future<int> dailyGoal() async => _dailyGoal;

  @override
  Future<void> setDailyGoal(int? words) async {
    if (words == null || words <= 0) return;
    _dailyGoal = words;
  }

  @override
  Future<int> writingStreak() async => _writingStreak;
}

/// An [AiRepository] that cannot reach the provider.
///
/// The assistant is a remote service: when it is not configured, the panel
/// says so instead of pretending to answer.
final class UnavailableAiRepository
    implements AiRepository, UnavailableService {
  /// Creates the repository.
  const UnavailableAiRepository();

  @override
  Stream<String> answer({
    required String projectId,
    required String question,
  }) => throw const ServiceUnavailableException();

  @override
  Stream<String> rewrite({
    required String sceneId,
    required String selection,
    required String instruction,
  }) => throw const ServiceUnavailableException();
}
