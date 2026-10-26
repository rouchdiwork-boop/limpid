import 'stripe_event_database.dart';

/// La table des événements Stripe traités, tenue en mémoire.
///
/// Elle est utilisée par la suite de tests et par les postes qui ne
/// configurent pas de base. Elle respecte le même invariant que
/// l'implémentation SQL : un événement ne peut être réservé qu'une fois,
/// et la libération rend la réservation à l'événement.
final class InMemoryStripeEventDatabase implements StripeEventDatabase {
  /// Crée une base vide.
  InMemoryStripeEventDatabase();

  final Map<String, StripeEventRecord> _events = <String, StripeEventRecord>{};

  @override
  Future<bool> claimEvent({
    required String eventId,
    required String type,
    required DateTime processedAt,
  }) async {
    if (_events.containsKey(eventId)) return false;
    _events[eventId] = StripeEventRecord(
      id: eventId,
      type: type,
      processedAt: processedAt,
    );
    return true;
  }

  @override
  Future<void> releaseEvent(String eventId) async {
    _events.remove(eventId);
  }

  @override
  Future<StripeEventRecord?> eventOf(String eventId) async => _events[eventId];

  /// Le nombre d'événements réservés.
  int get length => _events.length;
}
