/// La trace d'un événement Stripe déjà traité.
///
/// La trace est la clé d'idempotence du webhook : l'identifiant de
/// l'événement Stripe en est la clé, et son absence signifie que
/// l'événement n'a jamais été traité.
final class StripeEventRecord {
  /// Crée une trace.
  const StripeEventRecord({
    required this.id,
    required this.type,
    required this.processedAt,
  });

  /// L'identifiant de l'événement Stripe (`evt_…`).
  final String id;

  /// Le type de l'événement (`checkout.session.completed`…).
  final String type;

  /// Le moment où l'événement a été traité.
  final DateTime processedAt;
}

/// Le port de persistance des événements Stripe traités.
///
/// Le port ne porte aucune règle métier : il réserve l'identifiant d'un
/// événement et rend la trace. Le service du webhook décide de l'effet de
/// l'événement, et libère la réservation quand l'effet a échoué.
///
/// La table est celle de la migration `0014_stripe_events.sql`.
abstract interface class StripeEventDatabase {
  /// Réserve l'événement [eventId] pour traitement.
  ///
  /// Renvoie `true` quand la réservation est nouvelle : l'appelant est le
  /// premier à traiter l'événement. Renvoie `false` quand l'événement a
  /// déjà été réservé : l'effet ne doit alors pas être appliqué une seconde
  /// fois.
  ///
  /// La réservation est atomique : deux livraisons concurrentes du même
  /// événement ne peuvent pas s'attribuer la même réservation.
  Future<bool> claimEvent({
    required String eventId,
    required String type,
    required DateTime processedAt,
  });

  /// Libère la réservation de l'événement [eventId].
  ///
  /// La libération est faite quand l'effet a échoué : Stripe retente la
  /// livraison, et l'événement doit alors être traité comme s'il n'avait
  /// jamais été vu.
  Future<void> releaseEvent(String eventId);

  /// La trace de l'événement [eventId], `null` quand il est inconnu.
  Future<StripeEventRecord?> eventOf(String eventId);
}
