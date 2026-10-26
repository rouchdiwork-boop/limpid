import 'package:limpid_ai/src/budget/usage_meter.dart';
import 'package:limpid_ai/src/model/ai_error.dart';
import 'package:limpid_ai/src/model/ai_pricing.dart';
import 'package:limpid_ai/src/model/ai_provider_kind.dart';
import 'package:limpid_ai/src/model/ai_usage.dart';

/// Garde-fou de consommation IA.
///
/// Deux plafonds sont appliqués :
/// - par requête : nombre de tokens maximal (entrée + sortie) ;
/// - par jour : nombre de tokens et coût estimé maximaux.
///
/// Les compteurs sont fournis par un [UsageMeter], dont l'implémentation
/// réelle est injectée par l'API.
class BudgetGuard {
  /// Crée un garde-fou.
  const BudgetGuard({
    required this.meter,
    required this.maxTokensPerRequest,
    this.maxTokensPerDay,
    this.maxCostPerDayUsd,
  });

  /// Compteur de consommation.
  final UsageMeter meter;

  /// Plafond de tokens par requête (entrée + sortie).
  final int maxTokensPerRequest;

  /// Plafond de tokens par jour, si le plan en impose un.
  final int? maxTokensPerDay;

  /// Plafond de coût quotidien en dollars, si le plan en impose un.
  final double? maxCostPerDayUsd;

  /// Vérifie qu'un appel est autorisé, avant d'appeler la fournisseur.
  ///
  /// Lève [AiBudgetExceeded] si un plafond est atteint ou dépassé.
  Future<void> authorize({
    required int estimatedInputTokens,
    required int estimatedOutputTokens,
    required String userId,
    required String feature,
    String? taskKey,
    String? model,
  }) async {
    final int requestTokens = estimatedInputTokens + estimatedOutputTokens;

    if (requestTokens > maxTokensPerRequest) {
      throw AiBudgetExceeded(
        limit: maxTokensPerRequest,
        limitKind: 'request',
        details: <String, String>{
          'estimated_tokens': '$requestTokens',
          'feature': feature,
          if (taskKey != null) 'task': taskKey,
        },
      );
    }

    if (maxTokensPerDay == null && maxCostPerDayUsd == null) {
      return;
    }

    final AiUsageSnapshot snapshot = await meter.snapshot(userId);
    final int usedTokens = snapshot.totalTokens;

    if (maxTokensPerDay != null &&
        usedTokens + requestTokens > maxTokensPerDay!) {
      throw AiBudgetExceeded(
        limit: maxTokensPerDay!,
        limitKind: 'daily_tokens',
        details: <String, String>{
          'used_tokens': '$usedTokens',
          'estimated_tokens': '$requestTokens',
          'feature': feature,
          if (taskKey != null) 'task': taskKey,
        },
      );
    }

    final double? dailyCostLimit = maxCostPerDayUsd;
    if (dailyCostLimit == null) {
      return;
    }
    final double estimatedCost = model == null
        ? 0
        : AiPricing.estimateCostUsd(
            model,
            inputTokens: estimatedInputTokens,
            outputTokens: estimatedOutputTokens,
          );
    if (snapshot.estimatedCostUsd + estimatedCost > dailyCostLimit) {
      throw AiBudgetExceeded(
        limit: dailyCostLimit,
        limitKind: 'daily_cost',
        details: <String, String>{
          'used_cost_usd': snapshot.estimatedCostUsd.toStringAsFixed(6),
          'estimated_cost_usd': estimatedCost.toStringAsFixed(6),
          'feature': feature,
          if (taskKey != null) 'task': taskKey,
        },
      );
    }
  }

  /// Enregistre la consommation réelle d'un appel terminé.
  Future<void> record(
    AiUsage usage, {
    required String userId,
    required String feature,
    String? taskKey,
    AiProviderKind? provider,
  }) {
    return meter.record(
      usage,
      feature: feature,
      userId: userId,
      taskKey: taskKey,
      provider: provider,
    );
  }
}
