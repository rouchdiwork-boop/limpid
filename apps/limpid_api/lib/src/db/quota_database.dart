import 'package:limpid_core/limpid_core.dart';

import '../services/plan_catalog.dart';

/// La formule affectée à un compte.
///
/// L'affectation est la source de vérité du service de quota : elle porte
/// la formule choisie, le cycle de facturation, la période en cours et, le
/// cas échéant, la fin de l'essai gratuit.
final class AccountPlan {
  /// Crée une affectation de formule.
  const AccountPlan({
    required this.userId,
    required this.plan,
    required this.period,
    required this.periodStartedAt,
    this.trialEndsAt,
    this.periodEndsAt,
  });

  /// Le compte concerné.
  final String userId;

  /// La formule choisie.
  final SubscriptionPlan plan;

  /// Le cycle de facturation.
  final BillingPeriod period;

  /// Le moment où la période en cours a commencé.
  final DateTime periodStartedAt;

  /// Le moment où l'essai gratuit se termine, `null` hors essai.
  ///
  /// Le champ ne vaut `null` que lorsque l'abonnement a été confirmé : tant
  /// qu'il est renseigné, le compte est en essai, et la formule redevient
  /// « Gratuit » quand la date est passée.
  final DateTime? trialEndsAt;

  /// Le moment où la période de facturation se termine.
  final DateTime? periodEndsAt;

  /// Indique si l'essai du compte est terminé à [at].
  ///
  /// Un compte dont l'essai est échu retombe sur la formule gratuite.
  bool isTrialExpired(DateTime at) {
    final DateTime? end = trialEndsAt;
    if (end == null) return false;
    return !at.toUtc().isBefore(end.toUtc());
  }

  /// Indique si le compte est en essai à [at].
  bool isInTrial(DateTime at) {
    final DateTime? end = trialEndsAt;
    if (end == null) return false;
    return at.toUtc().isBefore(end.toUtc());
  }

  /// La représentation JSON de l'affectation.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'plan': plan.name,
      'period': period.name,
      'trial_ends_at': trialEndsAt?.toUtc().toIso8601String(),
      'period_started_at': periodStartedAt.toUtc().toIso8601String(),
      'period_ends_at': periodEndsAt?.toUtc().toIso8601String(),
    };
  }
}

/// La consommation d'un compte pour une fonctionnalité et une période.
final class QuotaUsage {
  /// Crée une consommation.
  const QuotaUsage({
    required this.userId,
    required this.feature,
    required this.periodKey,
    required this.quantity,
  });

  /// Le compte qui a consommé.
  final String userId;

  /// La fonctionnalité consommée.
  final QuotaFeature feature;

  /// La période de la consommation.
  final String periodKey;

  /// Le nombre d'unités consommées.
  final int quantity;
}

/// La persistance des formules et des compteurs de consommation.
///
/// Le port ne connaît ni le serveur HTTP ni les règles métier : il lit et
/// écrit les deux tables de la migration `0007_plans.sql`, et laisse le
/// service de quota comparer la consommation à la limite de la formule.
abstract interface class QuotaDatabase {
  /// La formule affectée au compte, `null` quand il n'en a pas.
  ///
  /// Un compte sans affectation est un compte gratuit : c'est le service de
  /// quota qui applique la formule « Gratuit », pas la base.
  Future<AccountPlan?> planOf(String userId);

  /// Enregistre la formule affectée au compte.
  ///
  /// L'écriture remplace l'affectation précédente : un compte porte une
  /// seule formule à la fois.
  Future<void> assignPlan(AccountPlan plan);

  /// La consommation du compte pour [feature] pendant [periodKey].
  Future<int> usageOf({
    required String userId,
    required QuotaFeature feature,
    required String periodKey,
  });

  /// Toutes les consommations du compte, toutes périodes confondues.
  ///
  /// Les périodes anciennes sont conservées : elles portent l'historique de
  /// consommation, et le service de quota n'en lit que la période courante.
  Future<List<QuotaUsage>> usagesOf(String userId);

  /// Ajoute [amount] à la consommation du compte pour [feature] pendant
  /// [periodKey].
  ///
  /// L'opération est atomique : deux écritures concurrentes ne perdent
  /// aucune unité.
  Future<void> consume({
    required String userId,
    required QuotaFeature feature,
    required String periodKey,
    int amount = 1,
  });
}
