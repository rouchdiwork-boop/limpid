import '../storage/object_storage.dart';
import 'kdp_record.dart';
import 'plan_lookup.dart';
import 'project_store.dart';
import 'sync_store.dart';

/// Le port de persistance de la publication Amazon KDP.
///
/// Le port donne accès au manuscrit (le projet et son journal), au
/// stockage des artefacts produits et à la trace des publications
/// préparées. L'API ne parle jamais directement au moteur : elle passe par
/// ce port, que la suite de tests remplace par une implémentation en
/// mémoire.
abstract interface class KdpDatabase {
  /// La lecture de la formule du compte.
  ///
  /// La publication Amazon KDP est réservée aux formules qui ouvrent les
  /// exports prêts à imprimer.
  PlanLookup get planLookup;

  /// Les projets, pour lire le livre à publier et l'accès de l'appelant.
  ProjectStore get projects;

  /// Le journal de synchronisation, pour reconstruire le manuscrit.
  SyncStore get sync;

  /// Le stockage des artefacts produits.
  ObjectStorage get artefacts;

  /// Enregistre la publication préparée et la renvoie.
  ///
  /// L'enregistrement est une **mise à jour** quand le projet porte déjà
  /// une fiche : l'identifiant de la fiche est conservé, seule sa trace
  /// est rafraîchie. Préparer deux fois le même livre laisse donc une
  /// fiche, jamais deux — et l'identifiant de la fiche ne change pas.
  ///
  /// La fiche rendue porte l'identifiant qui était le sien : un appelant
  /// qui ignore l'identifiant reçu reçoit l'identifiant stable.
  Future<KdpPublication> recordPublication(KdpPublication publication);

  /// Les publications du compte, les plus récentes d'abord.
  ///
  /// [projectId] restreint la liste à un projet ; quand il est absent, la
  /// liste porte toutes les publications du compte.
  Future<List<KdpPublication>> listPublications({
    required String userId,
    String? projectId,
  });

  /// La publication [publicationId], `null` quand elle n'existe pas ou
  /// quand elle appartient à un autre compte.
  Future<KdpPublication?> findPublication({
    required String publicationId,
    required String userId,
  });

  /// La fiche du projet [projectId], `null` quand le projet n'en porte pas.
  ///
  /// La lecture ne dépend pas du compte : un projet porte au plus une
  /// fiche, et c'est elle que la préparation reprend quand elle se répète.
  Future<KdpPublication?> findPublicationByProject({required String projectId});

  /// La fiche qui porte l'ISBN [isbn], `null` quand aucune fiche ne le
  /// porte.
  ///
  /// La lecture ne dépend pas du compte : elle sert à refuser un ISBN déjà
  /// pris par une autre fiche, même quand cette fiche appartient à un
  /// autre compte.
  Future<KdpPublication?> findPublicationByIsbn({required String isbn});
}
