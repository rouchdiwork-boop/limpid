import 'package:limpid_core/limpid_core.dart';

import '../db/admin_database.dart';
import '../db/feature_flag.dart';
import '../errors/app_exception.dart';
import '../logging/logger.dart';
import 'plan_catalog.dart';

/// Le port de lecture des indicateurs de fonctionnalité.
///
/// Le port est plus étroit que [AdminDatabase] : le service des indicateurs
/// ne liste pas les comptes et ne touche pas au journal d'audit. Un port
/// étroit se remplace par un double dans les tests, et il ne casse pas le
/// jour où le back-office gagne une méthode.
abstract interface class FeatureFlagSource {
  /// Les indicateurs de fonctionnalité, dans n'importe quel ordre.
  Future<List<FeatureFlag>> listFeatureFlags();
}

/// Un port de lecture qui puise dans un [AdminDatabase].
///
/// L'adaptateur est le point de branchement du service : le back-office
/// possède déjà la table des indicateurs, il n'en faut pas une seconde.
final class AdminFeatureFlagSource implements FeatureFlagSource {
  /// Crée un port sur la base [database].
  const AdminFeatureFlagSource(this._database);

  final AdminDatabase _database;

  @override
  Future<List<FeatureFlag>> listFeatureFlags() => _database.listFeatureFlags();
}

/// Le service des indicateurs de fonctionnalité.
///
/// Un indicateur est un **interrupteur général** : sa clef est celle d'une
/// capacité de formule ([PlanCapability]) et le couper éteint cette
/// capacité pour tout le monde, sans redéploiement et sans migration.
/// C'est l'outil de l'incident : un modèle qui répond n'importe quoi, une
/// recherche dans le manuscrit qui rend les données d'un autre livre.
///
/// ## La règle
///
/// - un indicateur **actif** laisse passer ;
/// - un indicateur **coupé** éteint la capacité qu'il porte, pour tous les
///   comptes, quelle que soit leur formule ;
/// - une clef qui n'est **pas** une capacité est **inerte** : c'est une
///   étiquette pour l'administrateur. Elle ne coupe rien et ne fait pas
///   échouer la requête.
///
/// ## La lecture
///
/// Un indicateur est consulté par chaque appel IA, chaque export, chaque
/// synchronisation : le lire en base à chaque fois serait ridicule. Le
/// service tient donc les indicateurs **en mémoire** et les recharge à deux
/// moments :
///
/// - sur demande, quand le back-office vient de changer un indicateur
///   ([reload]) : l'effet est immédiat sur l'instance qui écrit ;
/// - à la lecture, quand la copie en mémoire a [refreshInterval] de retard :
///   c'est le filet de sécurité qui voit le changement fait par une autre
///   instance du serveur ou directement en base.
///
/// Un rechargement échoué ne casse rien : le service garde le dernier état
/// connu et le signale dans le journal. Une coupure de la base ne doit pas
/// rendre le serveur muet sur toutes ses fonctionnalités.
final class FeatureFlagService {
  /// L'âge maximal de la copie en mémoire avant qu'elle soit rechargée.
  static const Duration defaultRefreshInterval = Duration(seconds: 15);

  /// Crée un service sur la source [source].
  ///
  /// [clock] rend l'heure injectable : les tests font passer le temps sans
  /// attendre.
  ///
  /// [logger] reçoit l'avertissement quand un rechargement échoue.
  FeatureFlagService({
    required this.source,
    required this.logger,
    this.refreshInterval = defaultRefreshInterval,
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  /// La source des indicateurs.
  final FeatureFlagSource source;

  /// Le journal des événements du serveur.
  final Logger logger;

  /// L'âge au-delà duquel la copie en mémoire est périmée.
  ///
  /// La valeur par défaut est courte : le but de l'interrupteur général est
  /// que la conduite change à la seconde, pas au bout d'une minute.
  final Duration refreshInterval;

  final DateTime Function() _clock;

  Map<String, FeatureFlag> _flags = const <String, FeatureFlag>{};
  Set<String> _cutKeys = const <String>{};
  DateTime? _loadedAt;
  Future<void>? _reloading;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Les indicateurs connus, en mémoire, par clef.
  ///
  /// La copie est en lecture seule : le service ne la change que par
  /// [reload].
  Map<String, FeatureFlag> get flags =>
      Map<String, FeatureFlag>.unmodifiable(_flags);

  /// Les capacités coupées à l'instant présent, par clef de capacité.
  ///
  /// La liste est en lecture seule : elle décrit l'état, elle ne le
  /// commande pas.
  Set<String> get cutCapabilities => Set<String>.unmodifiable(_cutKeys);

  /// L'instant du dernier rechargement réussi, `null` quand le service n'a
  /// encore rien lu.
  DateTime? get loadedAt => _loadedAt;

  /// Recharge les indicateurs depuis la source.
  ///
  /// La méthode ne lève pas : un rechargement échoué garde le dernier état
  /// connu et l'avertissement part dans le journal. Le rechargement est
  /// fait une seule fois : deux rechargements concurrents partagent la même
  /// lecture.
  Future<void> reload() async {
    final Future<void>? running = _reloading;
    if (running != null) {
      await running;
      return;
    }
    final Future<void> pass = _load();
    _reloading = pass;
    try {
      await pass;
    } finally {
      _reloading = null;
    }
  }

  /// Recharge les indicateurs quand la copie en mémoire a pris du retard.
  ///
  /// La méthode est appelée avant chaque lecture de l'état : c'est elle qui
  /// garantit qu'un changement fait ailleurs — une autre instance du
  /// serveur, une commande en base — finit par être vu, sans
  /// redéploiement.
  Future<void> refreshIfStale() async {
    final DateTime? loadedAt = _loadedAt;
    if (loadedAt != null) {
      final Duration age = _clock().toUtc().difference(loadedAt);
      if (age < refreshInterval) return;
    }
    await reload();
  }

  /// La fonctionnalité de nom [key] est-elle disponible à l'instant présent ?
  ///
  /// La méthode répond à l'**effet** de l'indicateur, pas à son état brut :
  /// une capacité est disponible tant que l'indicateur qui la porte n'est
  /// pas coupé. Une clef qui n'est pas une capacité est **inerte** : elle
  /// est toujours disponible, elle ne coupe rien.
  Future<bool> isEnabled(String key) async {
    await refreshIfStale();
    return !_cutKeys.contains(key);
  }

  /// La capacité [capability] est-elle coupée ?
  Future<bool> isCut(PlanCapability capability) async {
    await refreshIfStale();
    return _cutKeys.contains(capability.key);
  }

  /// Les capacités que la formule [plan] annonce, une capacité coupée
  /// enlevée.
  ///
  /// C'est la liste que `GET /v1/me/plan` renvoie : elle doit refléter
  /// l'état du jour, pas l'état du déploiement.
  Future<List<String>> announcedCapabilities(SubscriptionPlan plan) async {
    await refreshIfStale();
    return <String>[
      for (final PlanCapability capability in PlanCapability.values)
        if (PlanCatalog.hasCapability(plan, capability) &&
            !_cutKeys.contains(capability.key))
          capability.key,
    ];
  }

  /// Refuse la capacité [capability] quand elle est coupée.
  ///
  /// Jette une [ForbiddenException] qui nomme la fonctionnalité fautive :
  /// une capacité coupée par un indicateur se comporte comme une capacité
  /// absente de la formule.
  Future<void> ensureCapabilityAvailable(PlanCapability capability) async {
    await refreshIfStale();
    if (!_cutKeys.contains(capability.key)) return;
    throw ForbiddenException(
      message:
          'La fonctionnalité « ${capability.label} » est temporairement '
          'indisponible : elle a été coupée pour tout le monde.',
      details: <String, Object?>{
        'feature': capability.key,
        'disabled_by': 'feature_flag',
      },
    );
  }

  /// Lit les indicateurs et met le cache à jour.
  ///
  /// La lecture échouée est journalisée, jamais propagée : le service garde
  /// l'état qu'il connaît et réessaiera à la lecture suivante.
  Future<void> _load() async {
    try {
      final List<FeatureFlag> flags = await source.listFeatureFlags();
      _flags = _indexByKey(flags);
      _cutKeys = _cutCapabilities(_flags);
      _loadedAt = _clock().toUtc();
    } on Exception catch (error) {
      logger.warning('feature_flag.reload_failed', <String, Object?>{
        'error': error.toString(),
      });
    }
  }

  /// Les indicateurs par clef, la dernière ligne l'emportant.
  static Map<String, FeatureFlag> _indexByKey(List<FeatureFlag> flags) {
    final Map<String, FeatureFlag> indexed = <String, FeatureFlag>{};
    for (final FeatureFlag flag in flags) {
      indexed[flag.key] = flag;
    }
    return Map<String, FeatureFlag>.unmodifiable(indexed);
  }

  /// Les capacités coupées : un indicateur connu et **coupé**.
  ///
  /// Une clef inconnue est inerte : elle ne coupe rien, même coupée. Seules
  /// les clefs de capacité sont considérées.
  static Set<String> _cutCapabilities(Map<String, FeatureFlag> flags) {
    final Set<String> cut = <String>{};
    for (final PlanCapability capability in PlanCapability.values) {
      final FeatureFlag? flag = flags[capability.key];
      if (flag == null) continue;
      if (!flag.isEnabled) cut.add(capability.key);
    }
    return Set<String>.unmodifiable(cut);
  }
}
