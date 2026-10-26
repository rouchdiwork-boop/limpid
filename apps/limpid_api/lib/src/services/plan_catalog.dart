/// La lecture serveur du catalogue des formules de Limpid (D-15).
///
/// Les **plafonds** ne sont pas définis ici : ils vivent dans le domaine
/// partagé (`limpid_core`, `subscription_plan.dart`), qui décrit les quatre
/// formules de D-15. Ce fichier ne fait qu'expliquer, pour le serveur :
///
/// - quelle consommation est un **compteur** (un flux, remis à zéro par
///   période) et laquelle est une **jauge** (un stock, connu de l'appelant) ;
/// - dans quelle période un compteur se remet à zéro ;
/// - quelles capacités une formule ouvre.
///
/// Le service de quota lit donc ses limites dans `limpid_core` : aucun
/// plafond n'est redéfini dans l'API.
library;

import 'package:limpid_core/limpid_core.dart';

/// La durée de l'essai gratuit de la formule Écrivain, en jours (D-15).
///
/// Le domaine partagé ne porte pas la durée de l'essai : c'est la seule
/// donnée de D-15 que le catalogue du serveur doit connaître.
const int writerTrialDays = 14;

/// La durée d'un cycle de facturation mensuel, en jours.
const int monthlyCycleDays = 30;

/// La durée d'un cycle de facturation annuel, en jours.
const int yearlyCycleDays = 365;

/// La période de remise à zéro d'un compteur.
enum QuotaPeriod {
  /// La journée : le compteur repart à zéro chaque jour.
  day('day', 'Jour'),

  /// Le mois : le compteur repart à zéro chaque mois.
  month('month', 'Mois');

  const QuotaPeriod(this.key, this.label);

  /// Le nom technique de la période.
  final String key;

  /// Le nom affiché à l'auteur.
  final String label;

  /// La clé de la période contenant [at].
  ///
  /// La clé est stable et se trie comme une date : `2026-10` pour le mois,
  /// `2026-10-26` pour la journée.
  String keyAt(DateTime at) {
    final DateTime moment = at.toUtc();
    return switch (this) {
      QuotaPeriod.day =>
        '${moment.year}-${_two(moment.month)}-${_two(moment.day)}',
      QuotaPeriod.month => '${moment.year}-${_two(moment.month)}',
    };
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// La nature d'une consommation bornée par la formule.
enum QuotaFeatureKind {
  /// Un flux compté par le serveur, période par période.
  counter,

  /// Un stock, connu de l'appelant et comparé à la limite.
  gauge,
}

/// Une consommation bornée par la formule.
///
/// La période est `null` pour les jauges : leur valeur courante n'est pas
/// comptée par le serveur, elle lui est fournie par l'appelant.
enum QuotaFeature {
  /// Le nombre de projets du compte.
  projects('projects', 'Projets', QuotaFeatureKind.gauge, null),

  /// Le nombre de mots écrits sur l'ensemble du compte.
  words('words', 'Mots', QuotaFeatureKind.gauge, null),

  /// Le nombre d'exports produits dans le mois.
  exports('exports', 'Exports', QuotaFeatureKind.counter, QuotaPeriod.month),

  /// Le nombre de réécritures IA produites dans la journée.
  aiRewrites(
    'ai_rewrites',
    'Réécritures IA',
    QuotaFeatureKind.counter,
    QuotaPeriod.day,
  ),

  /// Le nombre de couvertures IA produites dans le mois.
  aiCovers(
    'ai_covers',
    'Couvertures IA',
    QuotaFeatureKind.counter,
    QuotaPeriod.month,
  ),

  /// Le nombre de jetons d'IA consommés dans le mois.
  ///
  /// C'est la grandeur que le marché vend : la maquette de la page
  /// tarifaire annonce « 500 k tokens / mois » et « 2 M tokens / mois ».
  /// Une formule qui ne vend pas de jetons n'a pas de limite ici.
  aiTokens(
    'ai_tokens',
    'Tokens IA',
    QuotaFeatureKind.counter,
    QuotaPeriod.month,
  ),

  /// Le stockage occupé par le compte, en octets.
  storageBytes('storage_bytes', 'Stockage', QuotaFeatureKind.gauge, null);

  const QuotaFeature(this.key, this.label, this.kind, this.period);

  /// Le nom technique de la fonctionnalité, stable dans la base.
  final String key;

  /// Le nom affiché à l'auteur.
  final String label;

  /// La nature de la consommation.
  final QuotaFeatureKind kind;

  /// La période de remise à zéro, `null` pour les jauges.
  final QuotaPeriod? period;

  /// La fonctionnalité de nom technique [key], `null` quand elle est
  /// inconnue.
  static QuotaFeature? fromKey(String key) {
    for (final QuotaFeature feature in QuotaFeature.values) {
      if (feature.key == key) return feature;
    }
    return null;
  }
}

/// Une capacité qu'une formule ouvre.
///
/// Les capacités listées ici sont celles que le domaine partagé connaît :
/// une formule qui n'a pas le drapeau correspondant n'ouvre pas la
/// fonctionnalité.
enum PlanCapability {
  /// La recherche dans le manuscrit (RAG).
  rag('rag', 'RAG sur le manuscrit'),

  /// Les exports prêts à imprimer.
  printReadyExports('print_ready_exports', 'Exports print-ready'),

  /// Le mode local, sans quitter la machine de l'auteur.
  localMode('local_mode', 'Mode local'),

  /// L'API publique et les webhooks.
  apiAndWebhooks('api_and_webhooks', 'API et webhooks');

  const PlanCapability(this.key, this.label);

  /// Le nom technique de la capacité.
  final String key;

  /// Le nom affiché à l'auteur.
  final String label;
}

/// Le catalogue des formules, vu par le serveur.
///
/// Le catalogue ne définit aucun plafond : il lit ceux du domaine partagé et
/// les présente au service de quota, qui les compare à la consommation.
abstract final class PlanCatalog {
  /// Les quatre formules, de la plus gratuite à la plus complète.
  static const List<SubscriptionPlan> all = <SubscriptionPlan>[
    SubscriptionPlan.free,
    SubscriptionPlan.writer,
    SubscriptionPlan.pro,
    SubscriptionPlan.studio,
  ];

  /// La description de la formule [plan], pour le cycle mensuel.
  static PlanDefinition definitionOf(SubscriptionPlan plan) =>
      PlanDefinition.of(plan);

  /// La description de la formule [plan], pour le cycle [period].
  ///
  /// Seule la formule Studio propose un cycle annuel (D-15).
  static PlanDefinition definitionFor(
    SubscriptionPlan plan,
    BillingPeriod period,
  ) {
    if (period == BillingPeriod.yearly && plan == SubscriptionPlan.studio) {
      return PlanDefinition.studioYearly;
    }
    return PlanDefinition.of(plan);
  }

  /// La durée de l'essai gratuit de la formule [plan], en jours.
  ///
  /// Elle vaut zéro quand la formule ne propose pas d'essai.
  static int trialDaysOf(SubscriptionPlan plan) {
    return plan == SubscriptionPlan.writer ? writerTrialDays : 0;
  }

  /// Indique si la formule propose un cycle annuel.
  ///
  /// Seule la formule Studio en propose un (D-15).
  static bool offersYearlyCycle(SubscriptionPlan plan) {
    return plan == SubscriptionPlan.studio;
  }

  /// Le plafond de [feature] pour la formule [plan].
  ///
  /// Il vaut `null` quand la formule n'interdit pas la fonctionnalité :
  /// D-15 l'accorde alors sans limite.
  static int? limitOf(SubscriptionPlan plan, QuotaFeature feature) {
    final PlanDefinition definition = PlanDefinition.of(plan);
    final PlanQuota quota = definition.quota;
    return switch (feature) {
      QuotaFeature.projects =>
        definition.isUnlimitedProjects ? null : quota.maxProjects,
      QuotaFeature.words => quota.maxWords,
      QuotaFeature.exports =>
        definition.isUnlimitedExports ? null : quota.maxExportsPerMonth,
      QuotaFeature.aiRewrites => quota.dailyAiRewrites,
      QuotaFeature.aiCovers => quota.monthlyAiCovers,
      // Une formule qui ne vend pas de jetons ne borne pas les jetons :
      // sa consommation reste encadrée par les autres compteurs.
      QuotaFeature.aiTokens =>
        quota.monthlyAiTokens == 0 ? null : quota.monthlyAiTokens,
      QuotaFeature.storageBytes => quota.maxStorageBytes,
    };
  }

  /// Indique si la formule ouvre la [capability].
  static bool hasCapability(SubscriptionPlan plan, PlanCapability capability) {
    final PlanDefinition definition = PlanDefinition.of(plan);
    return switch (capability) {
      PlanCapability.rag => definition.hasRag,
      PlanCapability.printReadyExports => definition.hasPrintReadyExport,
      PlanCapability.localMode => definition.hasLocalAi,
      PlanCapability.apiAndWebhooks => definition.hasApiAccess,
    };
  }

  /// La formule la moins chère qui ouvre [capability].
  ///
  /// Le garde-fou s'en sert pour nommer la formule à laquelle l'auteur
  /// doit monter.
  static SubscriptionPlan minimumTierFor(PlanCapability capability) {
    for (final SubscriptionPlan plan in all) {
      if (hasCapability(plan, capability)) return plan;
    }
    throw StateError('No plan provides ${capability.name}.');
  }

  /// La représentation JSON d'une formule du catalogue.
  static Map<String, Object?> toJson(SubscriptionPlan plan) {
    final PlanDefinition definition = PlanDefinition.of(plan);
    return <String, Object?>{
      'plan': plan.name,
      'name': definition.displayName,
      'price_cents': definition.priceInCents,
      'yearly_price_cents': offersYearlyCycle(plan)
          ? definitionFor(plan, BillingPeriod.yearly).priceInCents
          : null,
      'trial_days': trialDaysOf(plan),
      'seat_count': definition.quota.maxSeats,
      'quota': <String, Object?>{
        for (final QuotaFeature feature in QuotaFeature.values)
          feature.key: limitOf(plan, feature),
      },
      'capabilities': <String>[
        for (final PlanCapability capability in PlanCapability.values)
          if (hasCapability(plan, capability)) capability.key,
      ],
    };
  }
}
