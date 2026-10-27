import 'dart:convert';

import '../errors/app_exception.dart';
import 'payment_gateway.dart';

/// Les types d'événements Stripe que le webhook traite.
enum StripeEventType {
  /// Le paiement d'une session de paiement est confirmé.
  checkoutCompleted('checkout.session.completed'),

  /// Le paiement d'une session à paiement différé est confirmé.
  checkoutAsyncPaymentSucceeded('checkout.session.async_payment_succeeded'),

  /// La session de paiement a expiré sans que l'acheteur paye.
  ///
  /// L'événement ne rend aucun droit : il rend la place qu'une commande
  /// avait prise sur un code promo.
  checkoutExpired('checkout.session.expired'),

  /// L'abonnement du compte a changé.
  subscriptionUpdated('customer.subscription.updated'),

  /// L'abonnement du compte a été résilié.
  subscriptionDeleted('customer.subscription.deleted');

  const StripeEventType(this.key);

  /// Le nom technique de l'événement, tel que Stripe l'écrit.
  final String key;

  /// Le type d'événement nommé [raw], `null` quand il est inconnu.
  static StripeEventType? parse(String raw) {
    for (final StripeEventType type in StripeEventType.values) {
      if (type.key == raw) return type;
    }
    return null;
  }
}

/// Un événement Stripe, lu dans le corps d'une livraison.
///
/// L'événement ne garde que ce que le webhook utilise : l'identifiant, le
/// type et l'objet sur lequel porte l'événement. Le reste du corps — qui
/// porte les données de paiement — n'est ni copié, ni journalisé.
final class StripeEvent {
  /// Crée un événement.
  const StripeEvent({
    required this.id,
    required this.type,
    required this.object,
  });

  /// L'identifiant de l'événement (`evt_…`), la clé d'idempotence.
  final String id;

  /// Le type de l'événement, tel que Stripe l'écrit.
  final String type;

  /// L'objet sur lequel porte l'événement : la session, l'abonnement.
  final Map<String, Object?> object;

  /// L'événement lu dans le corps [body].
  ///
  /// Le corps est décodé tel quel : il n'est jamais re-sérialisé, sinon il
  /// ne correspondrait plus à la signature. Un corps qui n'est pas un objet
  /// JSON, ou qui ne porte ni identifiant ni type, est refusé.
  static StripeEvent decode(List<int> body) {
    final String raw;
    try {
      raw = utf8.decode(body);
    } on FormatException {
      throw const ValidationException(
        field: 'body',
        message: 'Le corps de la requête n\'est pas un texte UTF-8 valide.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const ValidationException(
        field: 'body',
        message: 'Le corps de la requête n\'est pas un JSON valide.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ValidationException(
        field: 'body',
        message: 'Le corps de la requête doit être un objet JSON.',
      );
    }
    return StripeEvent.parse(decoded);
  }

  /// L'événement lu dans le corps JSON [body].
  static StripeEvent parse(Map<String, dynamic> body) {
    final Object? rawId = body['id'];
    final Object? rawType = body['type'];
    if (rawId is! String || rawId.trim().isEmpty) {
      throw const ValidationException(
        field: 'body',
        message: 'L\'événement Stripe ne porte pas d\'identifiant.',
      );
    }
    if (rawType is! String || rawType.trim().isEmpty) {
      throw const ValidationException(
        field: 'body',
        message: 'L\'événement Stripe ne porte pas de type.',
      );
    }
    final Object? rawData = body['data'];
    final Object? rawObject = rawData is Map<String, dynamic>
        ? rawData['object']
        : null;
    if (rawObject is! Map<String, dynamic>) {
      throw const ValidationException(
        field: 'body',
        message: 'L\'événement Stripe ne porte pas d\'objet.',
      );
    }
    return StripeEvent(
      id: rawId.trim(),
      type: rawType.trim(),
      object: Map<String, Object?>.unmodifiable(rawObject),
    );
  }

  /// L'identifiant de l'objet Stripe sur lequel porte l'événement.
  ///
  /// C'est la référence du paiement : elle prouve l'acquisition de la
  /// formule.
  String? get reference {
    final Object? value = object['id'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// Les métadonnées portées par l'objet Stripe.
  ///
  /// Stripe y place le compte concerné et la formule payée : les deux sont
  /// écrits par le serveur du paiement, jamais par le client.
  Map<String, Object?> get metadata {
    final Object? value = object['metadata'];
    if (value is! Map<String, dynamic>) return const <String, Object?>{};
    return Map<String, Object?>.unmodifiable(value);
  }

  /// Le compte concerné par l'événement.
  ///
  /// Il est lu dans les métadonnées de l'objet, et repris dans la référence
  /// de la session quand les métadonnées sont absentes.
  String? get userId {
    final Object? fromMetadata = metadata['user_id'];
    if (fromMetadata is String && fromMetadata.trim().isNotEmpty) {
      return fromMetadata.trim();
    }
    final Object? fromReference = object['client_reference_id'];
    if (fromReference is String && fromReference.trim().isNotEmpty) {
      return fromReference.trim();
    }
    return null;
  }

  /// Le nom de la formule payée, lu dans les métadonnées de l'objet.
  String? get planKey {
    final Object? value = metadata['plan'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// L'état du paiement de la session, `null` quand l'objet n'en porte pas.
  String? get paymentStatus {
    final Object? value = object['payment_status'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// La commande est-elle l'achat d'un livre ?
  ///
  /// Le serveur écrit lui-même la marque dans les métadonnées de la
  /// session : le client ne peut pas la forger. Un abonnement ne porte
  /// jamais cette marque, et un achat de livre ne porte jamais de formule.
  bool get isBookPayment => metadata['kind'] == bookPaymentKind;

  /// La commande est-elle l'achat d'un bundle ?
  ///
  /// Comme la marque du livre, celle-ci est écrite par le serveur : le
  /// client ne peut pas la forger.
  bool get isBundlePayment => metadata['kind'] == bundlePaymentKind;

  /// Le bundle acheté, `null` quand l'événement n'est pas un achat de
  /// bundle.
  String? get bundleId {
    final Object? value = metadata['bundle_id'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// Le livre acheté, `null` quand l'événement n'est pas un achat de livre.
  String? get projectId {
    final Object? value = metadata['project_id'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// Le code promo appliqué à l'achat, `null` quand il n'y en a pas.
  String? get promoCode {
    final Object? value = metadata['promo_code'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// Le montant encaissé, en centimes.
  ///
  /// Le montant est celui que le prestataire a encaissé : il porte la
  /// remise du code promo. Il est `null` quand l'objet ne le porte pas,
  /// et le serveur se rabat alors sur le prix du livre.
  int? get amountTotal {
    final Object? value = object['amount_total'];
    if (value is num) return value.toInt();
    return null;
  }

  /// Le montant que le serveur a demande, en centimes.
  ///
  /// Le montant est ecrit par le serveur dans les metadonnees de la session
  /// : c'est le prix moins la remise. Il sert de repli quand le rappel ne
  /// porte pas le montant encaisse — la ventilation se fait alors sur le
  /// montant que l'acheteur a Paye, et non sur le prix plein.
  int? get chargedAmount {
    final Object? value = metadata['amount_cents'];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// L'état de l'abonnement, `null` quand l'objet n'en porte pas.
  String? get subscriptionStatus {
    final Object? value = object['status'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }
}
