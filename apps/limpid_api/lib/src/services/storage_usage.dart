import '../db/project_record.dart';
import '../db/project_store.dart';
import '../storage/artifact_keys.dart';
import '../storage/object_storage.dart';
import '../storage/stored_object.dart';

/// La mesure du stockage occupé par un compte.
///
/// La mesure est un **stock** : elle dit ce que le compte occupe à
/// l'instant, et non ce qu'il a consommé depuis le début du mois.
abstract interface class StorageUsage {
  /// Les octets occupés par les artefacts du compte [userId].
  Future<int> bytesOf(String userId);
}

/// La mesure du stockage d'un compte, lue dans le stockage objet.
///
/// Le stockage d'un compte est la somme de la taille de ses artefacts :
/// les exports de ses livres et l'archive de ses données personnelles.
///
/// Seuls les livres que le compte **possède** comptent : l'artefact d'un
/// livre partagé appartient à son propriétaire, comme le dit l'export des
/// données personnelles.
///
/// Un stockage qui ne sait pas lire ne donne aucune mesure : le compte
/// occupe alors zéro octet, et l'export reste impossible de toute façon.
final class AccountStorageUsage implements StorageUsage {
  /// Crée une mesure.
  const AccountStorageUsage({required this.projects, required this.storage});

  /// Les livres des comptes.
  final ProjectStore projects;

  /// Le stockage des artefacts.
  final ObjectStorage storage;

  @override
  Future<int> bytesOf(String userId) async {
    final ObjectStorageReader? reader = switch (storage) {
      final ObjectStorageReader capable => capable,
      _ => null,
    };
    if (reader == null) return 0;

    var total = 0;
    final List<ProjectRecord> visible = await projects.listAll(userId: userId);
    for (final ProjectRecord project in visible) {
      if (project.ownerId != userId) continue;
      total += await _bytesUnder(
        reader,
        ArtifactKeys.prefixOfProject(project.id),
      );
    }
    total += await _bytesUnder(reader, ArtifactKeys.prefixOfAccount(userId));
    return total;
  }

  /// Les octets occupés sous le préfixe [prefix].
  ///
  /// La liste des objets porte la taille de chaque artefact : la mesure
  /// ne lit aucun artefact.
  Future<int> _bytesUnder(ObjectStorageReader reader, String prefix) async {
    final List<StoredObject> objects = await reader.listObjects(prefix: prefix);
    var total = 0;
    for (final StoredObject object in objects) {
      total += object.sizeBytes;
    }
    return total;
  }
}
