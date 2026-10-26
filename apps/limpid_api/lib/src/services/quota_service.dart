import 'package:limpid_core/limpid_core.dart';

import '../db/quota_database.dart';
import '../errors/app_exception.dart';
import 'feature_flag_service.dart';
import 'plan_catalog.dart';
import 'quota_gauges.dart';
import 'webhook_dispatcher.dart';
import 'webhook_service.dart';

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
  /// Pour une jauge, c'est la valeur mesurée du compte : elle n'est
  /// jamais absente.
  final int used;

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
  ///
  /// [gauges] mesure les jauges du compte : le nombre de livres, le
  /// nombre de mots et le stockage occupé. Le port est facultatif, mais un
  /// service qui n'en a pas publie des jauges à zéro : la composition doit
  /// le câbler pour que la jauge porte la valeur réelle du compte.
  ///
  /// [dispatcher] porte les webhooks sortants du compte. Il est facultatif :
  /// un service qui n'a pas de dispatcher n'émet rien, il n'échoue pas
  /// non plus.
  QuotaService({
    required this.database,
    this.gauges,
    this.flags,
    DateTime Function()? clock,
    this.dispatcher,
  }) : _clock = clock ?? _utcNow;

  /// La base des formules et des compteurs.
  final QuotaDatabase database;

  /// Les indicateurs du back-office, `null` quand ils ne sont pas câblés.
  ///
  /// Un indicateur dont la clef est une capacité de formule coupe cette
  /// capacité pour tout le monde : c'est un interrupteur général, et il
  /// ne dépend pas de la formule.
  final FeatureFlagService? flags;

  /// Le port qui mesure les jauges du compte, `null` quand il n'est pas
  /// câblé.
  ///
  /// Les jauges sont les trois stocks de la formule : les livres, les mots
  /// et le stockage. Le serveur ne les compte pas, il les mesure.
  final QuotaGaugeReader? gauges;

  /// Le dispatcher des webhooks sortants, `null` quand le service n'en a pas.
  ///
  /// Le service est l'émetteur de deux événements du compte : le changement
  /// de formule et la jauge atteinte.
  final WebhookDispatcher? dispatcher;

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
    // L'interrupteur general passe avant la formule : une capacite coupee
    // par le back-office ne s'ouvre a personne, quelle que soit la
    // formule du compte.
    await flags?.ensureCapabilityAvailable(capability);

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
    _announceQuotaReached(
      userId: userId,
      feature: feature,
      limit: limit,
      used: used,
      period: period,
    );
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
  /// du compte, le nombre de mots écrits, le stockage qu'il occupe. La
  /// jauge est un compte d'éléments : la limite est le nombre d'éléments
  /// que le compte a le droit de porter, et le compte doit donc être en
  /// dessous de la limite.
  Future<void> ensureGauge({
    required String userId,
    required QuotaFeature feature,
    required int current,
  }) async {
    final AccountPlan plan = await planOf(userId);
    final int? limit = PlanCatalog.limitOf(plan.plan, feature);
    if (limit == null) return;
    if (current < limit) return;
    _announceQuotaReached(
      userId: userId,
      feature: feature,
      limit: limit,
      used: current,
      period: null,
    );
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

  /// Vérifie qu'une jauge tient dans la limite de la formule, une charge
  /// à venir comprise.
  ///
  /// [current] est la valeur relevée, [charge] la taille de ce que
  /// l'opération s'apprête à ajouter. La jauge est alors un volume : la
  /// limite est le volume que le compte a le droit d'occuper, et la
  /// somme de ce qu'il occupe déjà et de ce qu'il va écrire doit tenir
  /// dedans.
  ///
  /// La vérification précède l'écriture : un artefact refusé n'occupe
  /// rien, et le compte ne dépasse jamais son contrat.
  Future<void> ensureGaugeFits({
    required String userId,
    required QuotaFeature feature,
    required int current,
    required int charge,
  }) async {
    final AccountPlan plan = await planOf(userId);
    final int? limit = PlanCatalog.limitOf(plan.plan, feature);
    if (limit == null) return;
    final int total = current + charge;
    if (total <= limit) return;
    _announceQuotaReached(
      userId: userId,
      feature: feature,
      limit: limit,
      used: total,
      period: null,
    );
    throw PlanLimitException(
      message:
          'Le quota « ${feature.label} » de la formule '
          '${PlanCatalog.definitionOf(plan.plan).displayName} est atteint.',
      details: <String, Object?>{
        'feature': feature.key,
        'limit': limit,
        'used': total,
        'current': current,
        'charge': charge,
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
  ///
  /// Les jauges portent la valeur **mesurée** du compte : les livres qu'il
  /// possède, les mots qu'il a écrits, le stockage qu'il occupe. Les
  /// compteurs portent la consommation de la période courante.
  Future<QuotaSnapshot> snapshotOf(String userId) async {
    final AccountPlan plan = await planOf(userId);
    final DateTime now = _clock().toUtc();
    final List<QuotaUsage> usages = await database.usagesOf(userId);
    final QuotaGauges measured = await _measure(userId, plan);

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
            used: measured.valueOf(feature),
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

  /// La consommation d'un compteur du compte, dans la période courante.
  ///
  /// La mesure des jauges n'est pas déclenchée : un garde-fou qui ne lit
  /// qu'un compteur ne reconstruit pas les manuscrits du compte et ne
  /// liste pas son stockage.
  Future<QuotaCounter> counterOf({
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
    final DateTime now = _clock().toUtc();
    final String periodKey = period.keyAt(now);
    final int used = await database.usageOf(
      userId: userId,
      feature: feature,
      periodKey: periodKey,
    );
    return QuotaCounter(
      feature: feature,
      limit: PlanCatalog.limitOf(plan.plan, feature),
      used: used,
      period: period,
      periodKey: periodKey,
    );
  }

  /// Les jauges du compte, mesurées par le port de mesure.
  ///
  /// Un service sans port de mesure publie des jauges à zéro : il ne
  /// ment pas sur ce qu'il a mesuré, il dit qu'il n'a rien mesuré.
  Future<QuotaGauges> _measure(String userId, AccountPlan plan) async {
    final QuotaGaugeReader? reader = gauges;
    if (reader == null) return const QuotaGauges.empty();
    return reader.read(
      userId,
      wordCeiling: PlanCatalog.limitOf(plan.plan, QuotaFeature.words),
    );
  }

  /// Affecte une nouvelle formule au compte.
  ///
  /// L'essai gratuit est demandé explicitement : une formule qui n'en
  /// propose pas refuse la demande. Il ne se demande **qu'une fois** par
  /// compte.
  ///
  /// Une formule payée ne s'obtient pas par une demande du compte : elle
  /// vient d'un paiement, et [paymentReference] en porte la preuve. Sans
  /// cette preuve, la demande est refusée — le client ne s'attribue pas
  /// une formule qu'il n'a pas payée.
  Future<AccountPlan> changePlan({
    required String userId,
    required SubscriptionPlan plan,
    required BillingPeriod period,
    bool startTrial = false,
    String? paymentReference,
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
    final AccountPlan previous = await planOf(userId);
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
      if (previous.hasConsumedTrial) {
        throw const ConflictException(
          message:
              'Cet compte a déjà consommé son essai gratuit : il ne peut '
              'pas en demander un second.',
        );
      }
      trialEndsAt = now.add(Duration(days: trialDays));
    } else if (plan != SubscriptionPlan.free &&
        !_hasPayment(paymentReference)) {
      // L'essai est le chemin promotionnel : il ne demande pas de paiement.
      // Une formule payée, elle, vient d'un paiement.
      throw const ForbiddenException(
        message:
            'Une formule payée est activée par le paiement : elle ne se '
            'demande pas depuis le compte.',
      );
    }

    final AccountPlan assignment = AccountPlan(
      userId: userId,
      plan: plan,
      period: period,
      periodStartedAt: now,
      trialEndsAt: trialEndsAt,
      // L'essai est consommé pour toujours : le changer de formule ne le
      // rend pas.
      trialConsumedAt: previous.trialConsumedAt ?? (startTrial ? now : null),
      periodEndsAt: now.add(
        Duration(
          days: period == BillingPeriod.yearly
              ? yearlyCycleDays
              : monthlyCycleDays,
        ),
      ),
    );
    await database.assignPlan(assignment);
    _announcePlanChanged(
      userId: userId,
      previous: previous,
      assignment: assignment,
    );
    return assignment;
  }

  /// Annonce que la formule du compte [userId] a changé.
  ///
  /// La charge porte les deux formules et le cycle : elle ne porte ni la
  /// référence de paiement, ni le secret du point de rappel, ni la donnée
  /// d'un autre compte.
  void _announcePlanChanged({
    required String userId,
    required AccountPlan previous,
    required AccountPlan assignment,
  }) {
    dispatcher?.emit(
      userId: userId,
      event: WebhookEvent.planChanged,
      data: <String, Object?>{
        'plan': assignment.plan.name,
        'previous_plan': previous.plan.name,
        'period': assignment.period.name,
      },
    );
  }

  /// Annonce que la jauge de [feature] est atteinte.
  ///
  /// L'événement part avant le refus : l'auteur qui approche de sa limite
  /// est prévenu, et l'opération reste refusée.
  void _announceQuotaReached({
    required String userId,
    required QuotaFeature feature,
    required int limit,
    required int used,
    required QuotaPeriod? period,
  }) {
    dispatcher?.emit(
      userId: userId,
      event: WebhookEvent.quotaReached,
      data: <String, Object?>{
        'feature': feature.key,
        'limit': limit,
        'used': used,
        if (period != null) 'period': period.key,
      },
    );
  }

  /// La demande porte-t-elle la preuve d'un paiement.
  static bool _hasPayment(String? paymentReference) {
    final String reference = paymentReference?.trim() ?? '';
    return reference.isNotEmpty;
  }
}
