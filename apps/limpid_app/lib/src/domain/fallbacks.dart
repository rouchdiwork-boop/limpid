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

import 'package:limpid_app/src/domain/admin_repository.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/domain/search_repository.dart';
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
  final Map<SeriesId, Series> _series = <SeriesId, Series>{};
  final Map<VolumeId, Volume> _volumes = <VolumeId, Volume>{};
  final Map<ChapterId, Chapter> _chapters = <ChapterId, Chapter>{};
  final Map<SceneId, Scene> _scenes = <SceneId, Scene>{};
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
  Future<List<Chapter>> listChapters(String projectId) async {
    final List<Chapter> chapters = _chapters.values
        .where((Chapter chapter) => chapter.volumeId == null)
        .toList(growable: false);
    return List<Chapter>.unmodifiable(chapters);
  }

  @override
  Future<Chapter> saveChapter(Chapter chapter) async {
    _chapters[chapter.id] = chapter;
    return chapter;
  }

  @override
  Future<List<Scene>> listScenes(String chapterId) async {
    final List<Scene> scenes = _scenes.values
        .where((Scene scene) => scene.chapterId.value == chapterId)
        .toList(growable: false);
    return List<Scene>.unmodifiable(scenes);
  }

  @override
  Future<Scene> saveScene(Scene scene) async {
    _scenes[scene.id] = scene;
    return scene;
  }

  @override
  Future<List<Series>> listSeries(String projectId) async {
    final List<Series> series = _series.values
        .where((Series item) => item.projectId.value == projectId)
        .toList(growable: false);
    return List<Series>.unmodifiable(series);
  }

  @override
  Future<Series> createSeries({
    required String projectId,
    required String title,
    String synopsis = '',
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final Series series = Series(
      id: SeriesId(_ids.generate().toString()),
      projectId: ProjectId(projectId),
      title: title,
      synopsis: synopsis,
      order: OrderKey.between(_lastOrder, null),
      createdAt: now,
      updatedAt: now,
    );
    _lastOrder = series.order;
    _series[series.id] = series;
    return series;
  }

  @override
  Future<List<Volume>> listVolumes(String seriesId) async {
    final List<Volume> volumes = _volumes.values
        .where((Volume item) => item.seriesId.value == seriesId)
        .toList(growable: false);
    return List<Volume>.unmodifiable(volumes);
  }

  @override
  Future<Volume> createVolume({
    required String seriesId,
    required String title,
    String synopsis = '',
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final Volume volume = Volume(
      id: VolumeId(_ids.generate().toString()),
      seriesId: SeriesId(seriesId),
      title: title,
      synopsis: synopsis,
      order: OrderKey.between(_lastOrder, null),
      createdAt: now,
      updatedAt: now,
    );
    _lastOrder = volume.order;
    _volumes[volume.id] = volume;
    return volume;
  }

  @override
  Future<List<Chapter>> listChaptersOfVolume(String volumeId) async {
    final List<Chapter> chapters = _chapters.values
        .where((Chapter chapter) => chapter.volumeId?.value == volumeId)
        .toList(growable: false);
    return List<Chapter>.unmodifiable(chapters);
  }

  @override
  Future<Chapter> createChapter({
    required String projectId,
    String? volumeId,
    required String title,
    String synopsis = '',
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final Chapter chapter = Chapter(
      id: ChapterId(_ids.generate().toString()),
      volumeId: volumeId == null ? null : VolumeId(volumeId),
      title: title,
      synopsis: synopsis,
      order: OrderKey.between(_lastOrder, null),
      createdAt: now,
      updatedAt: now,
    );
    _lastOrder = chapter.order;
    _chapters[chapter.id] = chapter;
    return chapter;
  }

  @override
  Future<Scene> createScene({
    required String chapterId,
    required String title,
    String synopsis = '',
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final String id = _ids.generate().toString();
    final Scene scene = Scene(
      id: SceneId(id),
      chapterId: ChapterId(chapterId),
      documentId: DocumentId(id),
      title: title,
      synopsis: synopsis,
      order: OrderKey.between(_lastOrder, null),
      createdAt: now,
      updatedAt: now,
    );
    _lastOrder = scene.order;
    _scenes[scene.id] = scene;
    return scene;
  }

  @override
  Future<Scene> moveScene({
    required String sceneId,
    required int targetIndex,
  }) async {
    final Scene? scene = _scenes[SceneId(sceneId)];
    if (scene == null) {
      throw StateError('The scene "$sceneId" does not exist.');
    }
    final List<Scene> siblings = await listScenes(scene.chapterId.value);
    final List<Scene> remaining = siblings
        .where((Scene item) => item.id.value != sceneId)
        .toList(growable: false);
    final int index = targetIndex.clamp(0, remaining.length);
    final OrderKey? lower = index == 0 ? null : remaining[index - 1].order;
    final OrderKey? upper = index == remaining.length
        ? null
        : remaining[index].order;
    final Scene moved = scene.copyWith(
      order: OrderKey.between(lower, upper),
      updatedAt: DateTime.now().toUtc(),
    );
    _scenes[moved.id] = moved;
    return moved;
  }

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

/// A [PlanRepository] that cannot reach the backend.
///
/// The demonstration mode has no remote service: the billing screen says so
/// instead of showing a plan, a quota or a payment it never read.
final class UnavailablePlanRepository
    implements PlanRepository, UnavailableService {
  /// Creates the repository.
  const UnavailablePlanRepository();

  @override
  Future<AccountPlan> currentPlan() async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<PlanOffer>> offers() async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<QuotaReading>> usage() async =>
      throw const ServiceUnavailableException();

  @override
  Future<AccountPlan> changePlan({
    required SubscriptionPlan plan,
    required BillingPeriod period,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<CheckoutSession> openCheckout({
    required SubscriptionPlan plan,
    required BillingPeriod period,
    required Uri returnTo,
  }) async => throw const ServiceUnavailableException();
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

/// A [SearchRepository] that has no local database to search.
///
/// The search is **local**: without the database of the device, there is no
/// index to sweep. The repository refuses rather than pretending that the
/// books of the author hold no passage.
final class UnavailableSearchRepository
    implements SearchRepository, UnavailableService {
  /// Creates the repository.
  const UnavailableSearchRepository();

  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = defaultSearchLimit,
  }) async => throw const ServiceUnavailableException();
}

/// Un [AdminRepository] qui ne peut pas atteindre le serveur.
///
/// Le back-office n'existe que sur un serveur configure : l'ecran dit
/// alors que le service n'est pas disponible, il ne montre aucun compte.
final class UnavailableAdminRepository
    implements AdminRepository, UnavailableService {
  /// Cree le depot indisponible.
  const UnavailableAdminRepository();

  @override
  Future<List<AdminAccount>> accounts() async =>
      throw const ServiceUnavailableException();

  @override
  Future<AdminAccount> account(String userId) async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<AdminFeatureFlag>> featureFlags() async =>
      throw const ServiceUnavailableException();

  @override
  Future<AdminFeatureFlag> setFeatureFlag(
    String key, {
    required bool isEnabled,
  }) async => throw const ServiceUnavailableException();
}
