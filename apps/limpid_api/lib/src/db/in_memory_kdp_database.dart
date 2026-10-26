import '../storage/object_storage.dart';
import 'in_memory_project_store.dart';
import 'in_memory_sync_store.dart';
import 'kdp_database.dart';
import 'kdp_record.dart';
import 'plan_lookup.dart';
import 'project_store.dart';
import 'sync_store.dart';

/// La base des publications Amazon KDP tenue en mémoire, pour la suite de
/// tests.
///
/// L'implémentation garde les mêmes invariants que les bases SQL : une
/// publication appartient à un compte, les publications d'un compte sont
/// rendues les plus récentes d'abord et la trace n'est jamais partagée avec
/// un autre compte.
final class InMemoryKdpDatabase implements KdpDatabase {
  /// Crée une base vide.
  ///
  /// [planLookup] lit la formule du compte ; à défaut, le compte est traité
  /// comme « Gratuit ». [artefacts] reçoit les fichiers produits et
  /// [projects] et [sync] portent le manuscrit ; à défaut, la base tient
  /// des projets et un journal vides.
  InMemoryKdpDatabase({
    PlanLookup? planLookup,
    ObjectStorage? artefacts,
    ProjectStore? projects,
    SyncStore? sync,
  }) : _planLookup = planLookup ?? _freePlan,
       _artefacts = artefacts ?? InMemoryObjectStorage(),
       _projects = projects ?? InMemoryProjectStore(),
       _sync = sync ?? InMemorySyncStore();

  final PlanLookup _planLookup;
  final ObjectStorage _artefacts;
  final ProjectStore _projects;
  final SyncStore _sync;

  final Map<String, KdpPublication> _publications = <String, KdpPublication>{};

  /// Renvoie toujours `null` : le compte est traité comme « Gratuit ».
  static Future<String?> _freePlan(String userId) async => null;

  @override
  PlanLookup get planLookup => _planLookup;

  @override
  ProjectStore get projects => _projects;

  @override
  SyncStore get sync => _sync;

  @override
  ObjectStorage get artefacts => _artefacts;

  @override
  Future<KdpPublication> recordPublication(KdpPublication publication) async {
    _publications[publication.id] = publication;
    return publication;
  }

  @override
  Future<List<KdpPublication>> listPublications({
    required String userId,
    String? projectId,
  }) async {
    final List<KdpPublication> publications =
        _publications.values
            .where((KdpPublication publication) => publication.userId == userId)
            .where(
              (KdpPublication publication) =>
                  projectId == null || publication.projectId == projectId,
            )
            .toList()
          ..sort(_comparePublications);
    return List<KdpPublication>.unmodifiable(publications);
  }

  @override
  Future<KdpPublication?> findPublication({
    required String publicationId,
    required String userId,
  }) async {
    final KdpPublication? publication = _publications[publicationId];
    if (publication == null || publication.userId != userId) return null;
    return publication;
  }

  static int _comparePublications(KdpPublication left, KdpPublication right) {
    final int byDate = right.createdAt.compareTo(left.createdAt);
    if (byDate != 0) return byDate;
    return left.id.compareTo(right.id);
  }
}
