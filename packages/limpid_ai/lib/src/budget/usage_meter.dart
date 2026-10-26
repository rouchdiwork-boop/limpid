import 'package:limpid_ai/src/model/ai_provider_kind.dart';
import 'package:limpid_ai/src/model/ai_usage.dart';

/// Consommation cumulée sur la période courante (la journée, par défaut).
class AiUsageSnapshot {
  /// Crée un instantané de consommation.
  const AiUsageSnapshot({
    required this.totalTokens,
    required this.estimatedCostUsd,
  });

  /// Consommation vide.
  const AiUsageSnapshot.empty() : totalTokens = 0, estimatedCostUsd = 0;

  /// Total des tokens consommés.
  final int totalTokens;

  /// Coût cumulé estimé, en dollars américains.
  final double estimatedCostUsd;
}

/// Compteur de consommation IA.
///
/// L'implémentation réelle est fournie par l'API Limpid (base de données et
/// cache Redis). Ce package ne compte rien tout seul.
abstract class UsageMeter {
  /// Consommation courante d'un utilisateur sur la période en cours.
  Future<AiUsageSnapshot> snapshot(String userId);

  /// Enregistre la consommation d'un appel terminé.
  Future<void> record(
    AiUsage usage, {
    required String feature,
    required String userId,
    String? taskKey,
    AiProviderKind? provider,
  });
}

/// Compteur en mémoire, fourni à titre de référence.
///
/// Utile pour les tests et pour un serveur qui ne compte que sur une période
/// courte. Le contenu est perdu au redémarrage.
class InMemoryUsageMeter implements UsageMeter {
  /// Crée un compteur vide.
  InMemoryUsageMeter();

  final Map<String, AiUsageSnapshot> _snapshots = <String, AiUsageSnapshot>{};

  /// Consommation courante d'un utilisateur.
  AiUsageSnapshot snapshotOf(String userId) {
    return _snapshots[userId] ?? const AiUsageSnapshot.empty();
  }

  /// Remet le compteur d'un utilisateur à zéro (nouvelle période).
  void reset(String userId) {
    _snapshots.remove(userId);
  }

  @override
  Future<AiUsageSnapshot> snapshot(String userId) async => snapshotOf(userId);

  @override
  Future<void> record(
    AiUsage usage, {
    required String feature,
    required String userId,
    String? taskKey,
    AiProviderKind? provider,
  }) async {
    final AiUsageSnapshot current = snapshotOf(userId);
    _snapshots[userId] = AiUsageSnapshot(
      totalTokens: current.totalTokens + usage.totalTokens,
      estimatedCostUsd: current.estimatedCostUsd + usage.estimatedCostUsd,
    );
  }
}
