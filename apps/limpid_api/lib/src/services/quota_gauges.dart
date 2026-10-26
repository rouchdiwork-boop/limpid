import '../db/project_store.dart';
import '../db/sync_store.dart';
import '../storage/object_storage.dart';
import 'account_word_count.dart';
import 'plan_catalog.dart';
import 'storage_usage.dart';

/// Les jauges mesurées d'un compte.
///
/// Les jauges sont des stocks : leur valeur est celle du compte à
/// l'instant de la mesure, et non une consommation comptée par le
/// serveur.
final class QuotaGauges {
  /// Crée des jauges.
  const QuotaGauges({
    required this.projects,
    required this.words,
    required this.storageBytes,
  });

  /// Des jauges à zéro : un compte dont rien n'est mesuré.
  const QuotaGauges.empty() : projects = 0, words = 0, storageBytes = 0;

  /// Le nombre de livres du compte.
  final int projects;

  /// Le nombre de mots écrits par le compte.
  final int words;

  /// Le nombre d'octets occupés par le compte.
  final int storageBytes;

  /// La valeur de la jauge [feature].
  ///
  /// La méthode refuse une fonctionnalité qui n'est pas une jauge : c'est
  /// une erreur de programmation, pas une donnée absente.
  int valueOf(QuotaFeature feature) => switch (feature) {
    QuotaFeature.projects => projects,
    QuotaFeature.words => words,
    QuotaFeature.storageBytes => storageBytes,
    _ => throw StateError(
      'La fonctionnalité « ${feature.key} » n\'est pas une jauge.',
    ),
  };
}

/// Le port de mesure des jauges d'un compte.
///
/// Le port garde le service de quota testable sans base : un test injecte
/// les valeurs qu'il veut voir publiées.
abstract interface class QuotaGaugeReader {
  /// Les jauges du compte [userId], mesurées à l'instant.
  ///
  /// [wordCeiling] borne la mesure des mots : le compteur s'arrête au
  /// plafond de la formule et rend alors ce plafond.
  Future<QuotaGauges> read(String userId, {int? wordCeiling});
}

/// La mesure des jauges d'un compte.
///
/// Les trois jauges sont lues au même instant : l'état publié décrit le
/// compte tel qu'il est quand l'auteur ouvre son écran de formule.
final class AccountQuotaGauges implements QuotaGaugeReader {
  /// Crée une mesure.
  AccountQuotaGauges({
    required this.projects,
    required this.sync,
    required this.storage,
    this.pageLimit = AccountWordCounter.defaultWordCountPageLimit,
  });

  /// Les livres des comptes.
  final ProjectStore projects;

  /// Le journal de synchronisation des livres.
  final SyncStore sync;

  /// Le stockage des artefacts.
  final ObjectStorage storage;

  /// Le nombre de livres lus par page.
  final int pageLimit;

  @override
  Future<QuotaGauges> read(String userId, {int? wordCeiling}) async {
    final ProjectPage page = await projects.list(
      userId: userId,
      limit: 1,
      cursor: null,
    );
    final AccountWordCounter words = AccountWordCounter(
      projects: projects,
      sync: sync,
      pageLimit: pageLimit,
    );
    final AccountStorageUsage storageUsage = AccountStorageUsage(
      projects: projects,
      storage: storage,
    );
    return QuotaGauges(
      projects: page.total,
      words: await words.countOf(userId, ceiling: wordCeiling),
      storageBytes: await storageUsage.bytesOf(userId),
    );
  }
}
