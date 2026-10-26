import 'dart:math';

import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_core/limpid_core.dart';

/// La durée pendant laquelle deux commandes de paiement partagent la même
/// clé d'idempotence, en millisecondes.
///
/// Quinze minutes : assez pour absorber un double-clic et une reprise
/// d'une session encore ouverte, trop court pour ressusciter une session
/// de paiement expirée.
const int checkoutKeyWindowMs = 15 * 60 * 1000;

/// Le nombre d'octets de l'entropie du nonce d'un dépôt.
const int _nonceBytes = 16;

/// La formule, les quotas et le paiement de l'auteur, servis par l'API.
///
/// Les trois routes de lecture décrivent la formule du compte, ses
/// compteurs et le catalogue public. Les deux routes d'écriture changent la
/// formule et ouvrent une session de paiement.
///
/// Le client ne laisse jamais sortir une exception brute : un échec est
/// toujours l'un des types de `domain/errors.dart`, ou
/// `ServiceUnavailableException` quand le paiement n'est pas configuré.
final class ApiPlanRepository implements PlanRepository {
  /// Crée un dépôt sur le dessus de [client].
  ///
  /// [clock] rend l'heure injectable : les tests font passer le temps sans
  /// attendre. Le dépôt tire un **nonce** à sa naissance : il rend la clé
  /// d'idempotence opaque, et deux dépôts ne se confondent jamais.
  ApiPlanRepository({
    required this.client,
    this.checkoutOrigin,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _nonce = _newNonce();

  /// Le client de l'API.
  final ApiClient client;

  /// L'origine publique de l'application, quand elle est connue.
  ///
  /// Le paiement renvoie l'auteur sur cette origine : sans elle, le service
  /// de paiement n'est pas configuré sur ce poste et la session ne peut pas
  /// s'ouvrir. La composition racine décide — l'écran ne connaît jamais
  /// l'adresse du site.
  final Uri? checkoutOrigin;

  /// L'heure courante.
  final DateTime Function() _clock;

  /// Le nonce du dépôt, tiré une fois pour toutes.
  final String _nonce;

  @override
  Future<AccountPlan> currentPlan() async {
    final Object? payload = await client.get('/v1/me/plan');
    final Map<String, Object?> data = _objectOf(payload);
    final SubscriptionPlan plan = _planOf(data['plan']);
    return AccountPlan(
      plan: plan,
      displayName: _stringOf(data['name']) ?? plan.name,
      status:
          PlanStatus.fromKey(_stringOf(data['status']) ?? '') ??
          PlanStatus.free,
      period: _periodOf(data['period']),
      periodStartedAt:
          _momentOf(data['period_started_at']) ?? DateTime.now().toUtc(),
      periodEndsAt: _momentOf(data['period_ends_at']),
      trialEndsAt: _momentOf(data['trial_ends_at']),
      seatCount: _intOf(data['seat_count']) ?? 1,
    );
  }

  @override
  Future<List<PlanOffer>> offers() async {
    final Object? payload = await client.get('/v1/plans');
    if (payload is! List<dynamic>) {
      throw const ApiMalformedResponseException(
        'The API did not return the list of the plans.',
      );
    }
    final List<PlanOffer> offers = <PlanOffer>[];
    for (final Object? item in payload) {
      offers.add(_offerOf(_objectOf(item)));
    }
    return List<PlanOffer>.unmodifiable(offers);
  }

  @override
  Future<List<QuotaReading>> usage() async {
    final Object? payload = await client.get('/v1/me/quota');
    final Map<String, Object?> data = _objectOf(payload);
    final Object? quotas = data['quotas'];
    if (quotas is! List<dynamic>) {
      throw const ApiMalformedResponseException(
        'The API did not return the counters of the quotas.',
      );
    }

    final Map<QuotaMeter, QuotaReading> readings = <QuotaMeter, QuotaReading>{};
    for (final Object? item in quotas) {
      final Map<String, Object?> counter = _objectOf(item);
      final QuotaMeter? meter = _meterOf(_stringOf(counter['feature']));
      if (meter == null) continue;
      readings[meter] = QuotaReading(
        meter: meter,
        limit: _intOf(counter['limit']),
        used: _intOf(counter['used']),
      );
    }

    // Une grandeur que le serveur ne publie pas reste présente, vide :
    // l'écran garde ses trois jauges plutôt que d'en perdre une.
    return List<QuotaReading>.unmodifiable(<QuotaReading>[
      for (final QuotaMeter meter in QuotaMeter.values)
        readings[meter] ?? QuotaReading(meter: meter),
    ]);
  }

  @override
  Future<AccountPlan> changePlan({
    required SubscriptionPlan plan,
    required BillingPeriod period,
  }) async {
    final Object? payload = await client.post(
      '/v1/me/plan',
      body: <String, Object?>{'plan': plan.name, 'period': period.name},
    );
    final Map<String, Object?> data = _objectOf(payload);
    final SubscriptionPlan changed = _planOf(data['plan']);
    final DateTime? trialEndsAt = _momentOf(data['trial_ends_at']);
    return AccountPlan(
      plan: changed,
      displayName: _stringOf(data['name']) ?? changed.name,
      status: _statusOf(changed, trialEndsAt),
      period: _periodOf(data['period']),
      periodStartedAt:
          _momentOf(data['period_started_at']) ?? DateTime.now().toUtc(),
      periodEndsAt: _momentOf(data['period_ends_at']),
      trialEndsAt: trialEndsAt,
    );
  }

  @override
  Future<CheckoutSession> openCheckout({
    required SubscriptionPlan plan,
    required BillingPeriod period,
    required Uri returnTo,
  }) async {
    final Uri? origin = checkoutOrigin;
    if (origin == null) {
      // L'application ne connaît pas son adresse publique : elle ne peut
      // pas renvoyer l'auteur vers l'écran d'abonnement après le paiement.
      throw const ServiceUnavailableException();
    }
    final Uri target = origin.resolve(returnTo.toString());
    final Object? payload = await client.post(
      '/v1/checkout',
      body: <String, Object?>{
        'plan': _checkoutKeyOf(plan, period),
        'success_url': target.toString(),
        'cancel_url': target.toString(),
      },
      // Un double-clic sur « Payer » ne doit pas ouvrir deux sessions de
      // paiement : la cle d'idempotence fait rejouer la premiere reponse
      // au lieu de creer une seconde session.
      headers: <String, String>{
        'idempotency-key': _idempotencyKeyOf(plan, period),
      },
    );
    final Map<String, Object?> data = _objectOf(payload);
    return CheckoutSession(
      id: _stringOf(data['session_id']) ?? '',
      url: _stringOf(data['url']) ?? '',
      status: _stringOf(data['status']) ?? 'open',
    );
  }

  /// La formule d'une réponse du serveur.
  static PlanOffer _offerOf(Map<String, Object?> data) {
    final SubscriptionPlan plan = _planOf(data['plan']);
    final Map<String, Object?> quota = _mapOf(data['quota']);
    return PlanOffer(
      plan: plan,
      displayName: _stringOf(data['name']) ?? plan.name,
      priceInCents: _intOf(data['price_cents']) ?? 0,
      yearlyPriceInCents: _intOf(data['yearly_price_cents']),
      trialDays: _intOf(data['trial_days']) ?? 0,
      seatCount: _intOf(data['seat_count']) ?? 1,
      maxWords: _intOf(quota['words']),
      maxAiUsage: _intOf(quota['ai_rewrites']),
      maxStorageBytes: _intOf(quota['storage_bytes']),
    );
  }

  /// La grandeur mesurée par le compteur de nom [feature].
  ///
  /// Le serveur compte six fonctionnalités ; l'écran n'en montre que
  /// trois : les mots, l'usage de l'IA et le stockage.
  static QuotaMeter? _meterOf(String? feature) => switch (feature) {
    'words' => QuotaMeter.words,
    'ai_rewrites' => QuotaMeter.aiUsage,
    'ai_tokens' => QuotaMeter.aiTokens,
    'ai_covers' => QuotaMeter.aiCovers,
    'storage_bytes' => QuotaMeter.storage,
    _ => null,
  };

  /// L'état d'un abonnement, déduit de sa formule et de son essai.
  static PlanStatus _statusOf(SubscriptionPlan plan, DateTime? trialEndsAt) {
    if (plan == SubscriptionPlan.free) return PlanStatus.free;
    final DateTime? end = trialEndsAt;
    if (end == null) return PlanStatus.active;
    return end.isAfter(DateTime.now().toUtc())
        ? PlanStatus.trial
        : PlanStatus.active;
  }

  /// La clé d'idempotence d'une commande de paiement.
  ///
  /// La clé tient dans une **fenêtre de temps** : deux clics dans la même
  /// fenêtre jouent la même commande — le second reçoit la reponse du
  /// premier — et une commande reprise plus tard ouvre une session neuve,
  /// parce que l'ancienne a pu expirer.
  String _idempotencyKeyOf(SubscriptionPlan plan, BillingPeriod period) {
    final int window =
        _clock().toUtc().millisecondsSinceEpoch ~/ checkoutKeyWindowMs;
    return 'checkout-$_nonce-${plan.name}-${period.name}-$window';
  }

  /// La clé d'une formule pour le service de paiement.
  ///
  /// Le serveur distingue le cycle annuel par un suffixe : `studio` pour le
  /// cycle mensuel, `studio_yearly` pour le cycle annuel.
  static String _checkoutKeyOf(SubscriptionPlan plan, BillingPeriod period) {
    final String name = plan.name;
    return period == BillingPeriod.yearly ? '${name}_yearly' : name;
  }

  /// Tire un nonce qui rend la clé d'idempotence opaque.
  ///
  /// Le nonce n'est pas un secret : il sert à ce que deux dépôts ne
  /// partagent jamais la même clé.
  static String _newNonce() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(
      _nonceBytes,
      (int _) => random.nextInt(256),
      growable: false,
    );
    return bytes
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Map<String, Object?> _objectOf(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const ApiMalformedResponseException(
      'The API did not return the expected payload.',
    );
  }

  static Map<String, Object?> _mapOf(Object? value) {
    if (value is Map<String, Object?>) return value;
    return const <String, Object?>{};
  }

  static String? _stringOf(Object? value) {
    if (value is String) return value;
    return null;
  }

  static int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static DateTime? _momentOf(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static SubscriptionPlan _planOf(Object? value) {
    final String name = _stringOf(value) ?? '';
    for (final SubscriptionPlan plan in SubscriptionPlan.values) {
      if (plan.name == name) return plan;
    }
    throw ApiMalformedResponseException(
      "The API returned an unknown plan: '$name'.",
    );
  }

  static BillingPeriod _periodOf(Object? value) {
    final String name = _stringOf(value) ?? '';
    for (final BillingPeriod period in BillingPeriod.values) {
      if (period.name == name) return period;
    }
    return BillingPeriod.monthly;
  }
}
