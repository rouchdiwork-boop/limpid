import 'package:limpid_core/limpid_core.dart';

import '../db/quota_database.dart';
import '../errors/app_exception.dart';
import 'plan_catalog.dart';

/// L'état d'une formule pour un compte.
enum PlanStatus {
  /// La formule gratuite, sans abonnement ni essai.
  free('free', 'Formule gratuite'),

  /// Un essai gratuit en cours.
  trial('trial', 'Essai gratuit'),

  /// Un abonnement actif.
  active('active', 'Abonnement actif');

  const PlanStatus(this.key, this.label);

  /// Le nom technique de l'état.
  final String key;

  /// Le nom affiché à l'auteur.
  final String label;
}

/// La consommation d'une fonctionnalité, avec sa limite.
final class QuotaCounter {
  /// Crée un compteur.
  const QuotaCounter({
    required this.feature,
    required this.limit,
    required this.used,
    required this.period,
    required this.periodKey,
  });

  /// La fonctionnalité comptée.
  final QuotaFeature feature;

  /// Le plafond de la formule, `null` quand la formule est illimitée.
  final int? limit;

  /// La consommation de la période courante.
  ///
  /// Elle vaut `null` pour les jauges : leur valeur n'est pas comptée par
  /// le serveur, elle lui est fournie par l'appelant.
  final int? used;

  /// La période de remise à zéro, `null` pour les jauges.
  final QuotaPeriod? period;

  /// La clé de la période courante, `null` pour les jauges.
  final String? periodKey;

  /// La représentation JSON du compteur.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'feature': feature.key,
      'kind': feature.kind.name,
      'limit': limit,
      'used': used,
      'period': period?.key,
      'period_key': periodKey,
    };
  }
}

/// L'état des quotas d'un compte.
final class QuotaSnapshot {
  /// Crée un état.
  const QuotaSnapshot({
    required this.plan,
    required this.definition,
    required this.counters,
  });

  /// La formule effective du compte.
  final AccountPlan plan;

  /// La description de la formule effective.
  final PlanDefinition definition;

  /// Les compteurs, un par fonctionnalité.
  final List<QuotaCounter> counters;

  /// La représentation JSON de l'état.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'plan': plan.plan.name,
      'period': plan.period.name,
      'quotas': <Object?>[
        for (final QuotaCounter counter in counters) counter.toJson(),
      ],
    };
  }
}

/// Le garde-fou des quotas.
///
/// Le service lit la formule du compte, compare la consommation à la limite
/// de la formule et **jette** l'erreur qui nomme la fonctionnalité fautive.
/// La vérification précède toujours la consommation : une opération refusée
/// ne coûte rien au compte.
final class QuotaService {
  /// Crée un service.
  ///
  /// [clock] rend l'heure injectable : les tests font passer le temps sans
  /// attendre.
  QuotaService({required this.database, DateTime Function()? clock})
    : _clock = clock ?? _utcNow;

  /// La base des formules et des compteurs.
  final QuotaDatabase database;

  /// L'heure courante, en UTC.
  final DateTime Function() _clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// La formule effective du compte.
  ///
  /// Un compte sans affectation est un compte gratuit. Un compte dont
  /// l'essai est terminé retombe sur la formule gratuite : l'abonnement
  /// n'est confirmé qu'après le paiement.
  Future<AccountPlan> planOf(String userId) async {
    final DateTime now = _clock().toUtc();
    final AccountPlan? stored = await database.planOf(userId);
    if (stored == null) {
      return AccountPlan(
        userId: userId,
        plan: SubscriptionPlan.free,
        period: BillingPeriod.monthly,
        periodStartedAt: now,
      );
    }
    if (!stored.isTrialExpired(now)) return stored;
    return AccountPlan(
      userId: userId,
      plan: SubscriptionPlan.free,
      period: stored.period,
      periodStartedAt: stored.periodStartedAt,
      trialEndsAt: stored.trialEndsAt,
      periodEndsAt: stored.periodEndsAt,
    );
  }

  /// La description de la formule effective du compte.
  Future<PlanDefinition> definitionOf(String userId) async {
    final AccountPlan plan = await planOf(userId);
    return PlanCatalog.definitionOf(plan.plan);
  }

  /// L'état de la formule du compte.
  Future<PlanStatus> statusOf(String userId) async {
    final AccountPlan plan = await planOf(userId);
    if (plan.plan == SubscriptionPlan.free) return PlanStatus.free;
    if (plan.isInTrial(_clock().toUtc())) return PlanStatus.trial;
    return PlanStatus.active;
  }

  /// Vérifie que la formule du compte ouvre [capability].
  ///
  /// Jette une [PlanLimitException] quand la fonctionnalité n'est pas
  /// incluse dans la formule.
  Future<void> ensureCapability({
    required String userId,
    required PlanCapability capability,
  }) async {
    final AccountPlan plan = await planOf(userId);
    if (PlanCatalog.hasCapability(plan.plan, capability)) return;
    final SubscriptionPlan required = PlanCatalog.minimumTierFor(capability);
    throw PlanLimitException(
      message:
          "La fonctionnalité « ${capability.label} » n'est pas incluse dans "
          'la formule ${PlanCatalog.definitionOf(plan.plan).displayName}. '
          'Passez à la formule '
          '${PlanCatalog.definitionOf(required).displayName} pour y accéder.',
      details: <String, Object?>{
        'feature': capability.key,
        'plan': plan.plan.name,
        'required_plan': required.name,
      },
    );
  }

  /// Vérifie que le compteur de [feature] n'est pas épuisé.
  ///
  /// La consommation est lue dans la période courante : un compteur dont la
  /// période est passée ne bloque jamais l'opération.
  Future<void> ensureCounter({
    required String userId,
    required QuotaFeature feature,
  }) async {
    final QuotaPeriod? period = feature.period;
    if (period == null) {
      throw StateError(
        'La fonctionnalité « ${feature.key} » est une jauge, pas un compteur.',
      );
    }
    final AccountPlan plan = await planOf(userId);
    final int? limit = PlanCatalog.limitOf(plan.plan, feature);
    if (limit == null) return;
    final DateTime now = _clock().toUtc();
    final String periodKey = period.keyAt(now);
    final int used = await database.usageOf(
      userId: userId,
      feature: feature,
      periodKey: periodKey,
    );
    if (used < limit) return;
    throw PlanLimitException(
      message:
          'Le quota « ${feature.label} » de la formule '
          '${PlanCatalog.definitionOf(plan.plan).displayName} est atteint.',
      details: <String, Object?>{
        'feature': feature.key,
        'limit': limit,
        'used': used,
        'period': period.key,
        'period_key': periodKey,
      },
    );
  }

  /// Vérifie qu'une jauge tient dans la limite de la formule.
  ///
  /// [current] est la valeur relevée par l'appelant : le nombre de projets
  /// du compte, le nombre de mots écrits, le stockage qu'il occupe.
  Future<void> ensureGauge({
    required String userId,
    required QuotaFeature feature,
    required int current,
  }) async {
    final AccountPlan plan = await planOf(userId);
    final int? limit = PlanCatalog.limitOf(plan.plan, feature);
    if (limit == null) return;
    if (current < limit) return;
    throw PlanLimitException(
      message:
          'Le quota « ${feature.label} » de la formule '
          '${PlanCatalog.definitionOf(plan.plan).displayName} est atteint.',
      details: <String, Object?>{
        'feature': feature.key,
        'limit': limit,
        'used': current,
      },
    );
  }

  /// Enregistre la consommation d'une unité de [feature].
  ///
  /// L'appel se fait **après** le succès de l'opération : une opération
  /// refusée ou en échec ne consomme rien.
  Future<void> recordConsumption({
    required String userId,
    required QuotaFeature feature,
    int amount = 1,
  }) async {
    final QuotaPeriod? period = feature.period;
    if (period == null) {
      throw StateError(
        'La fonctionnalité « ${feature.key} » est une jauge, pas un compteur.',
      );
    }
    await database.consume(
      userId: userId,
      feature: feature,
      periodKey: period.keyAt(_clock().toUtc()),
      amount: amount,
    );
  }

  /// L'état des quotas du compte.
  Future<QuotaSnapshot> snapshotOf(String userId) async {
    final AccountPlan plan = await planOf(userId);
    final DateTime now = _clock().toUtc();
    final List<QuotaUsage> usages = await database.usagesOf(userId);

    final Map<String, int> consumed = <String, int>{};
    for (final QuotaUsage usage in usages) {
      consumed['${usage.feature.key}|${usage.periodKey}'] = usage.quantity;
    }

    final List<QuotaCounter> counters = <QuotaCounter>[];
    for (final QuotaFeature feature in QuotaFeature.values) {
      final QuotaPeriod? period = feature.period;
      final int? limit = PlanCatalog.limitOf(plan.plan, feature);
      if (period == null) {
        counters.add(
          QuotaCounter(
            feature: feature,
            limit: limit,
            used: null,
            period: null,
            periodKey: null,
          ),
        );
        continue;
      }
      final String periodKey = period.keyAt(now);
      counters.add(
        QuotaCounter(
          feature: feature,
          limit: limit,
          used: consumed['${feature.key}|$periodKey'] ?? 0,
          period: period,
          periodKey: periodKey,
        ),
      );
    }

    return QuotaSnapshot(
      plan: plan,
      definition: PlanCatalog.definitionOf(plan.plan),
      counters: List<QuotaCounter>.unmodifiable(counters),
    );
  }

  /// Affecte une nouvelle formule au compte.
  ///
  /// L'essai gratuit est demandé explicitement : une formule qui n'en
  /// propose pas refuse la demande.
  Future<AccountPlan> changePlan({
    required String userId,
    required SubscriptionPlan plan,
    required BillingPeriod period,
    bool startTrial = false,
  }) async {
    final DateTime now = _clock().toUtc();
    if (period == BillingPeriod.yearly &&
        !PlanCatalog.offersYearlyCycle(plan)) {
      throw ValidationException(
        field: 'period',
        message:
            'La formule ${PlanCatalog.definitionOf(plan).displayName} ne '
            'propose pas de cycle annuel.',
      );
    }
    DateTime? trialEndsAt;
    if (startTrial) {
      final int trialDays = PlanCatalog.trialDaysOf(plan);
      if (trialDays <= 0) {
        throw ValidationException(
          field: 'start_trial',
          message:
              'La formule ${PlanCatalog.definitionOf(plan).displayName} ne '
              'propose pas d\'essai gratuit.',
        );
      }
      trialEndsAt = now.add(Duration(days: trialDays));
    }

    final AccountPlan assignment = AccountPlan(
      userId: userId,
      plan: plan,
      period: period,
      periodStartedAt: now,
      trialEndsAt: trialEndsAt,
      periodEndsAt: now.add(
        Duration(
          days: period == BillingPeriod.yearly
              ? yearlyCycleDays
              : monthlyCycleDays,
        ),
      ),
    );
    await database.assignPlan(assignment);
    return assignment;
  }
}
