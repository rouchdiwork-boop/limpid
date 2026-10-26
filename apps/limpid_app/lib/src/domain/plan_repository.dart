/// La formule, les quotas et le paiement de l'auteur.
///
/// Le contrat vit dans la couche domaine : l'écran de facturation le
/// nomme, l'implémentation de la couche données le réalise — aucun des deux
/// ne connaît l'autre. Les types qu'il manipule sont **immuables** : l'écran
/// lit un état, il ne le modifie jamais.
library;

import 'package:limpid_core/limpid_core.dart';

/// L'état de l'abonnement d'un compte.
enum PlanStatus {
  /// La formule gratuite, sans abonnement ni essai.
  free,

  /// Un essai gratuit en cours.
  trial,

  /// Un abonnement actif.
  active;

  /// L'état de nom [key], `null` quand le nom est inconnu.
  ///
  /// Un nom inconnu ne fait jamais échouer la lecture : l'écran montre alors
  /// l'état gratuit, qui est le plus prudent.
  static PlanStatus? fromKey(String key) {
    for (final PlanStatus status in PlanStatus.values) {
      if (status.name == key) return status;
    }
    return null;
  }
}

/// Les trois grandeurs que l'usage du cycle montre.
enum QuotaMeter {
  /// Les mots écrits sur l'ensemble du compte.
  words,

  /// L'usage de l'IA.
  ///
  /// Le serveur mesure cet usage en opérations d'IA — réécritures et
  /// couvertures — et non en tokens : c'est la seule unité qu'il publie.
  aiUsage,

  /// Le stockage occupé par le compte.
  storage,
}

/// La lecture d'un compteur : sa limite et sa consommation.
///
/// Une limite absente signifie que la formule n'interdit pas la
/// fonctionnalité ; une consommation absente signifie que personne ne la
/// mesure encore. L'écran distingue les deux : une jauge sans mesure reste
/// vide plutôt que d'inventer une consommation.
final class QuotaReading {
  /// Crée une lecture.
  const QuotaReading({required this.meter, this.limit, this.used});

  /// La grandeur mesurée.
  final QuotaMeter meter;

  /// Le plafond de la formule, `null` quand elle n'en pose pas.
  final int? limit;

  /// La consommation de la période courante, `null` quand elle est inconnue.
  final int? used;

  /// Indique si la formule ne pose aucune limite sur cette grandeur.
  bool get isUnlimited => limit == null;

  /// Indique si la consommation et la limite sont toutes deux connues.
  bool get isMeasured => limit != null && used != null;

  /// Le taux de consommation, entre 0 et 1.
  ///
  /// Une grandeur sans limite, sans mesure ou sans plafond reste à zéro :
  /// la jauge ne remplit jamais une barre qu'elle ne sait pas mesurer.
  double get ratio {
    final int? limit = this.limit;
    final int? used = this.used;
    if (limit == null || used == null || limit <= 0) return 0;
    if (used >= limit) return 1;
    return used / limit;
  }
}

/// L'abonnement du compte.
final class AccountPlan {
  /// Crée un abonnement.
  const AccountPlan({
    required this.plan,
    required this.displayName,
    required this.status,
    required this.period,
    required this.periodStartedAt,
    this.periodEndsAt,
    this.trialEndsAt,
    this.seatCount = 1,
  });

  /// La formule du compte.
  final SubscriptionPlan plan;

  /// Le nom de la formule, tel que le serveur l'écrit.
  final String displayName;

  /// L'état de l'abonnement.
  final PlanStatus status;

  /// Le cycle de facturation en cours.
  final BillingPeriod period;

  /// Le moment où la période a commencé.
  final DateTime periodStartedAt;

  /// Le moment où la période se termine, `null` quand il est inconnu.
  final DateTime? periodEndsAt;

  /// Le moment où l'essai gratuit se termine, `null` hors essai.
  final DateTime? trialEndsAt;

  /// Le nombre de sièges de la formule.
  final int seatCount;

  /// Indique si le compte est en essai gratuit.
  bool get isInTrial => status == PlanStatus.trial;

  /// Indique si le compte est en abonnement actif.
  bool get isActive => status == PlanStatus.active;
}

/// Une formule du catalogue, avec ses limites.
///
/// Les limites valent `null` quand la formule n'en pose pas : l'écran
/// n'affiche alors aucune ligne pour cette grandeur, plutôt qu'un chiffre
/// qu'il n'a pas.
final class PlanOffer {
  /// Crée une formule du catalogue.
  const PlanOffer({
    required this.plan,
    required this.displayName,
    required this.priceInCents,
    this.yearlyPriceInCents,
    this.trialDays = 0,
    this.seatCount = 1,
    this.maxWords,
    this.maxAiUsage,
    this.maxStorageBytes,
  });

  /// La formule.
  final SubscriptionPlan plan;

  /// Le nom de la formule, tel que le serveur l'écrit.
  final String displayName;

  /// Le prix mensuel, en centimes d'euro.
  final int priceInCents;

  /// Le prix annuel, en centimes d'euro, `null` quand la formule ne
  /// propose pas de cycle annuel.
  final int? yearlyPriceInCents;

  /// La durée de l'essai gratuit, en jours.
  final int trialDays;

  /// Le nombre de sièges de la formule.
  final int seatCount;

  /// Le nombre maximum de mots, `null` quand la formule n'en pose pas.
  final int? maxWords;

  /// La limite de l'usage de l'IA, `null` quand la formule n'en pose pas.
  final int? maxAiUsage;

  /// Le nombre maximum d'octets de stockage, `null` quand la formule n'en
  /// pose pas.
  final int? maxStorageBytes;

  /// Indique si la formule propose le cycle [period].
  bool offers(BillingPeriod period) =>
      period == BillingPeriod.monthly || yearlyPriceInCents != null;

  /// Le prix de la formule pour le cycle [period], en centimes d'euro.
  ///
  /// Une formule qui ne propose pas le cycle demandé garde le prix de son
  /// cycle mensuel : l'écran n'affiche jamais un prix annuel qui n'existe
  /// pas.
  int priceFor(BillingPeriod period) {
    final int? yearly = yearlyPriceInCents;
    if (period == BillingPeriod.yearly && yearly != null) return yearly;
    return priceInCents;
  }

  /// Le cycle que le prix affiché suit.
  BillingPeriod periodOf(BillingPeriod period) {
    if (period == BillingPeriod.yearly && yearlyPriceInCents != null) {
      return BillingPeriod.yearly;
    }
    return BillingPeriod.monthly;
  }
}

/// Une session de paiement ouverte par le serveur.
final class CheckoutSession {
  /// Crée une session.
  const CheckoutSession({
    required this.id,
    required this.url,
    this.status = 'open',
  });

  /// L'identifiant de la session.
  final String id;

  /// L'adresse où l'auteur paie son abonnement.
  final String url;

  /// L'état de la session.
  final String status;
}

/// Le port de la formule, des quotas et du paiement.
///
/// L'écran de facturation lit ce port et n'atteint jamais le serveur. La
/// doublure par défaut refuse les appels et dit pourquoi : un écran ne
/// présente jamais un abonnement qu'il n'a pas lu.
abstract interface class PlanRepository {
  /// L'abonnement du compte.
  ///
  /// Lève une erreur typée quand le serveur refuse la lecture ou ne peut
  /// pas être atteint.
  Future<AccountPlan> currentPlan();

  /// Les formules du catalogue, avec leurs limites.
  Future<List<PlanOffer>> offers();

  /// La consommation du cycle en cours.
  ///
  /// Une lecture par grandeur : les trois jauges de l'écran de formule.
  Future<List<QuotaReading>> usage();

  /// Change la formule du compte.
  ///
  /// Le serveur trace le changement dans son journal d'audit et refuse la
  /// demande quand ce journal n'est pas câblé.
  Future<AccountPlan> changePlan({
    required SubscriptionPlan plan,
    required BillingPeriod period,
  });

  /// Ouvre une session de paiement pour la formule [plan].
  ///
  /// L'auteur est renvoyé sur [returnTo] quand le paiement aboutit ou quand
  /// il l'abandonne.
  ///
  /// Lève `ServiceUnavailableException` quand le service de paiement n'est
  /// pas configuré sur ce poste : l'écran le dit au lieu de laisser croire
  /// qu'un paiement a commencé.
  Future<CheckoutSession> openCheckout({
    required SubscriptionPlan plan,
    required BillingPeriod period,
    required Uri returnTo,
  });
}
