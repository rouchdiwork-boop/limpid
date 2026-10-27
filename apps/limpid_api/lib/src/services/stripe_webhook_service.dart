import '../db/audit_log.dart';
import '../db/stripe_event_database.dart';
import '../errors/app_exception.dart';
import '../logging/logger.dart';
import 'book_sale_service.dart';
import 'bundle_service.dart';
import 'quota_service.dart';
import 'stripe_event.dart';
import 'stripe_plan_attribution.dart';
import 'stripe_signature.dart';

/// L'effet du service sur une livraison Stripe.
enum StripeWebhookOutcome {
  /// La formule du compte a été attribuée, changée ou retirée.
  applied('applied'),

  /// L'événement avait déjà été traité : aucun effet n'a été appliqué.
  replayed('replayed'),

  /// L'événement ne concernait pas l'abonnement du compte.
  ignored('ignored');

  const StripeWebhookOutcome(this.key);

  /// Le nom technique de l'issue, stable dans les journaux.
  final String key;
}

/// Le résultat du traitement d'une livraison Stripe.
final class StripeWebhookResult {
  /// Crée un résultat.
  const StripeWebhookResult({
    required this.eventId,
    required this.eventType,
    required this.outcome,
    this.action,
  });

  /// L'identifiant de l'événement traité.
  final String eventId;

  /// Le type de l'événement traité.
  final String eventType;

  /// L'effet appliqué.
  final StripeWebhookOutcome outcome;

  /// L'action tracée dans le journal d'audit, `null` quand il n'y en a pas.
  final String? action;
}

/// Le service du webhook Stripe.
///
/// Le service est le chemin normal d'attribution d'une formule payée : c'est
/// lui, et non le client, qui décide de la formule du compte à partir d'un
/// paiement confirmé (D-37). La route d'administration reste le filet de
/// sécurité manuel.
///
/// Le service est **idempotent** : Stripe renvoie la même livraison
/// plusieurs fois, et l'effet ne doit être appliqué qu'une fois. La clé
/// d'idempotence est l'identifiant de l'événement Stripe.
///
/// Le service ne journalise jamais le corps de la livraison : il porte des
/// données de paiement.
final class StripeWebhookService {
  /// Crée le service.
  ///
  /// [secret] est le secret du point de rappel Stripe. Il est facultatif :
  /// un poste qui ne l'a pas ne sert pas le webhook, et la route répond un
  /// refus propre au lieu de faire échouer le démarrage du serveur.
  ///
  /// [handledEvents] restreint les types d'événements traités. Vide, le
  /// service traite tous les types de l'abonnement.
  StripeWebhookService({
    required this.database,
    required this.quota,
    required this.audit,
    this.secret,
    this.logger,
    this.bookSales,
    this.bundles,
    DateTime Function()? clock,
    this.tolerance = defaultStripeSignatureTolerance,
    List<String> handledEvents = const <String>[],
  }) : _clock = clock ?? _utcNow,
       _handledEvents = _resolveHandledEvents(handledEvents),
       _attribution = StripePlanAttribution(
         quota: quota,
         audit: audit,
         logger: logger,
       );

  /// La table des événements Stripe déjà traités.
  final StripeEventDatabase database;

  /// Le service qui porte les formules et les quotas.
  final QuotaService quota;

  /// Le journal d'audit.
  final AuditLog audit;

  /// Le secret du point de rappel Stripe, `null` quand il n'est pas
  /// configuré.
  final String? secret;

  /// Le journal du serveur, `null` quand le service est sans journal.
  ///
  /// Il ne reçoit jamais le corps de la livraison : il ne porte que des
  /// identifiants.
  final Logger? logger;

  /// Le service de la vente des livres, quand le serveur vend des livres.
  ///
  /// Il est facultatif : un serveur qui ne vend pas de livre attribue des
  /// formules et rien d'autre. Quand il est là, le webhook traite **aussi**
  /// le paiement d'un livre : il accorde le droit de lecture et écrit la
  /// ventilation des revenus.
  final BookSaleService? bookSales;

  /// Le service des bundles, quand le serveur vend des bundles.
  ///
  /// Il est facultatif : un serveur qui ne vend pas de bundle attribue des
  /// formules et rien d'autre. Quand il est là, le webhook traite **aussi**
  /// le paiement d'un bundle : il accorde le droit de lecture sur chaque
  /// livre du bundle et écrit la ventilation des revenus.
  final BundleService? bundles;

  /// La tolérance de l'horodatage de la signature.
  final Duration tolerance;

  final DateTime Function() _clock;
  final Set<String> _handledEvents;
  final StripePlanAttribution _attribution;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Le webhook est-il configuré ?
  ///
  /// Un poste sans secret ne sert pas le webhook : la route répond un refus
  /// propre au lieu de faire échouer le serveur.
  bool get isConfigured {
    final String? value = secret;
    return value != null && value.trim().isNotEmpty;
  }

  /// Les types d'événements que le service traite.
  Set<String> get handledEvents => Set<String>.unmodifiable(_handledEvents);

  /// Traite la livraison d'un événement Stripe.
  ///
  /// [payload] est le corps **tel quel** : il est vérifié par la signature
  /// avant d'être décodé, et il n'est jamais journalisé. [signature] est
  /// l'en-tête `Stripe-Signature` de la livraison.
  ///
  /// La livraison est refusée quand la signature est invalide, quand
  /// l'horodatage est hors de la tolérance, ou quand le secret n'est pas
  /// configuré.
  Future<StripeWebhookResult> handle({
    required List<int> payload,
    required String? signature,
    String? ip,
  }) async {
    if (!isConfigured) {
      throw const ServiceUnavailableException(
        message:
            'Le webhook Stripe n\'est pas configuré sur ce poste : la '
            'livraison est refusée.',
      );
    }
    final StripeSignatureVerdict verdict = StripeSignatureVerifier(
      secret: secret!,
      tolerance: tolerance,
    ).verify(header: signature, payload: payload, now: _clock());
    if (verdict != StripeSignatureVerdict.valid) {
      logger?.warning('stripe.webhook.signature_refused', <String, Object?>{
        'verdict': verdict.name,
      });
      // Le même refus pour les trois verdicts : l'appelant n'apprend pas
      // quelle partie de la signature il a devinée juste.
      throw const UnauthorizedException(
        message: 'La signature de la livraison Stripe est invalide.',
      );
    }

    final StripeEvent event = StripeEvent.decode(payload);
    final StripeEventType? type = StripeEventType.parse(event.type);
    if (type == null || !_handledEvents.contains(type.key)) {
      _log('stripe.webhook.ignored', event);
      return StripeWebhookResult(
        eventId: event.id,
        eventType: event.type,
        outcome: StripeWebhookOutcome.ignored,
      );
    }

    final DateTime now = _clock();
    final bool claimed = await database.claimEvent(
      eventId: event.id,
      type: event.type,
      processedAt: now,
    );
    if (!claimed) {
      // Stripe a renvoyé la même livraison : l'effet a déjà été appliqué.
      _log('stripe.webhook.replayed', event);
      return StripeWebhookResult(
        eventId: event.id,
        eventType: event.type,
        outcome: StripeWebhookOutcome.replayed,
      );
    }

    try {
      final String? action = await _apply(event, type: type, ip: ip);
      _log('stripe.webhook.handled', event);
      return StripeWebhookResult(
        eventId: event.id,
        eventType: event.type,
        outcome: action == null
            ? StripeWebhookOutcome.ignored
            : StripeWebhookOutcome.applied,
        action: action,
      );
    } on Object catch (error, stackTrace) {
      // L'effet a échoué : la réservation est rendue, pour que la
      // nouvelle tentative de Stripe traite l'événement comme s'il
      // n'avait jamais été vu.
      await database.releaseEvent(event.id);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Applique l'effet de l'événement, et rend l'action tracée dans le
  /// journal d'audit.
  Future<String?> _apply(
    StripeEvent event, {
    required StripeEventType type,
    String? ip,
  }) {
    return switch (type) {
      StripeEventType.checkoutCompleted ||
      StripeEventType.checkoutAsyncPaymentSucceeded => _applyCheckout(
        event,
        ip: ip,
      ),
      StripeEventType.subscriptionUpdated =>
        _attribution.applySubscriptionUpdate(event, ip: ip),
      StripeEventType.subscriptionDeleted => _attribution.applyCancellation(
        event,
        ip: ip,
      ),
      StripeEventType.checkoutExpired => _releaseExpiredCheckout(event),
    };
  }

  /// Rend la place qu'une commande abandonnée avait prise.
  ///
  /// Une session de paiement qui expire sans que l'acheteur paie ne rend
  /// aucun droit : elle rend l'usage d'un code promo. Sans cette libération,
  /// le quota d'un code s'épuise sous des commandes abandonnées, et le code
  /// devient inutilisable pour les acheteurs qui, eux, paient.
  ///
  /// La libération est idempotente : Stripe peut livrer l'événement
  /// plusieurs fois, et la place ne peut rendre deux fois.
  Future<String?> _releaseExpiredCheckout(StripeEvent event) async {
    final BookSaleService? sales = bookSales;
    final String? userId = event.userId;
    final String? code = event.promoCode;
    if (sales == null || userId == null || code == null) {
      // Sans code promo, la session expiree ne prend aucune place : il n'y a
      // rien a rendre.
      return null;
    }
    await sales.releasePromo(code: code, buyerId: userId);
    _log('stripe.webhook.checkout_expired', event);
    return null;
  }

  /// Applique l'effet d'un paiement de session de paiement.
  ///
  /// Trois commandes portent le même événement : l'abonnement d'une formule,
  /// l'achat d'un livre et l'achat d'un bundle. Le serveur les distingue par
  /// la marque qu'il écrit lui-même dans les métadonnées de la session. Un
  /// paiement de livre ou de bundle n'attribue aucune formule : il accorde
  /// un droit de lecture et écrit la ventilation des revenus.
  Future<String?> _applyCheckout(StripeEvent event, {String? ip}) async {
    if (event.isBundlePayment) {
      return _applyBundleCheckout(event, ip: ip);
    }
    if (!event.isBookPayment) {
      return _attribution.applyPayment(event, ip: ip);
    }
    final BookSaleService? sales = bookSales;
    if (sales == null) {
      logger?.warning('stripe.webhook.book_sales_absent', <String, Object?>{
        'event_id': event.id,
        'event_type': event.type,
      });
      return null;
    }
    if (event.paymentStatus != 'paid') {
      logger?.info('stripe.webhook.payment_not_confirmed', <String, Object?>{
        'event_id': event.id,
        'event_type': event.type,
        'payment_status': event.paymentStatus,
      });
      return null;
    }
    final String? userId = event.userId;
    final String? projectId = event.projectId;
    final String? reference = event.reference;
    if (userId == null || projectId == null || reference == null) {
      logger?.warning(
        'stripe.webhook.book_payment_unresolved',
        <String, Object?>{'event_id': event.id, 'event_type': event.type},
      );
      return null;
    }
    return sales.applyPayment(
      buyerId: userId,
      projectId: projectId,
      source: reference,
      amountInCents: _amountOf(event),
      promoCode: event.promoCode,
      ip: ip,
    );
  }

  /// Applique l'effet d'un paiement de bundle.
  ///
  /// Le paiement d'un bundle accorde le droit de lecture sur **chaque**
  /// livre du bundle, et la ventilation se fait sur le montant encaissé :
  /// la remise d'un code promo ne sort jamais de la poche de l'auteur.
  Future<String?> _applyBundleCheckout(StripeEvent event, {String? ip}) async {
    final BundleService? bundles = this.bundles;
    if (bundles == null) {
      logger?.warning('stripe.webhook.bundles_absent', <String, Object?>{
        'event_id': event.id,
        'event_type': event.type,
      });
      return null;
    }
    if (event.paymentStatus != 'paid') {
      logger?.info('stripe.webhook.payment_not_confirmed', <String, Object?>{
        'event_id': event.id,
        'event_type': event.type,
        'payment_status': event.paymentStatus,
      });
      return null;
    }
    final String? userId = event.userId;
    final String? bundleId = event.bundleId;
    final String? reference = event.reference;
    if (userId == null || bundleId == null || reference == null) {
      logger?.warning(
        'stripe.webhook.bundle_payment_unresolved',
        <String, Object?>{'event_id': event.id, 'event_type': event.type},
      );
      return null;
    }
    return bundles.applyPayment(
      buyerId: userId,
      bundleId: bundleId,
      source: reference,
      amountInCents: _amountOf(event),
      promoCode: event.promoCode,
      ip: ip,
    );
  }

  /// Le montant que la ventilation doit reproduire.
  ///
  /// Le montant est celui que le prestataire a encaissé ; quand le rappel ne
  /// le porte pas, c'est celui que le serveur avait demandé, écrit dans les
  /// métadonnées de la session. Quand les deux manquent, l'anomalie est
  /// dite : la ventilation se rabattra sur le prix affiché, qui est le
  /// dernier recours.
  int? _amountOf(StripeEvent event) {
    final int? amount = event.amountTotal ?? event.chargedAmount;
    if (amount == null) {
      logger?.warning('stripe.webhook.amount_unknown', <String, Object?>{
        'event_id': event.id,
        'event_type': event.type,
      });
    }
    return amount;
  }

  /// Trace le traitement d'un événement.
  ///
  /// La trace ne porte que des identifiants : ni le corps de la livraison,
  /// ni les données de paiement.
  void _log(String message, StripeEvent event) {
    logger?.info(message, <String, Object?>{
      'event_id': event.id,
      'event_type': event.type,
    });
  }

  /// Les types d'événements que le service traite.
  ///
  /// La liste par défaut couvre l'abonnement : la confirmation d'un
  /// paiement, le changement de formule et l'annulation. Une liste venue de
  /// l'environnement ne garde que les types connus : une valeur erronée ne
  /// désactive donc pas le webhook.
  static Set<String> _resolveHandledEvents(List<String> configured) {
    final Set<String> known = <String>{
      for (final StripeEventType type in StripeEventType.values) type.key,
    };
    if (configured.isEmpty) return known;
    final Set<String> selected = <String>{
      for (final String key in configured)
        if (known.contains(key.trim().toLowerCase())) key.trim().toLowerCase(),
    };
    return selected.isEmpty ? known : selected;
  }
}
