import 'package:postgres/postgres.dart';

import 'stripe_event_database.dart';

/// L'implémentation Postgres du port [StripeEventDatabase].
///
/// La réservation d'un événement est portée par la base : l'insertion
/// `ON CONFLICT DO NOTHING` n'écrit la ligne que la première fois, et le
/// nombre de lignes touchées dit si la réservation est nouvelle.
///
/// Les horodatages sont envoyés comme `TIMESTAMPTZ`, la convention du
/// dialecte Postgres.
final class PostgresStripeEventDatabase implements StripeEventDatabase {
  /// Crée un port sur le [pool].
  const PostgresStripeEventDatabase(this._pool);

  /// Le pool de connexions.
  final Pool<Object?> _pool;

  @override
  Future<bool> claimEvent({
    required String eventId,
    required String type,
    required DateTime processedAt,
  }) async {
    final Result result = await _pool.execute(
      'INSERT INTO stripe_events (event_id, event_type, processed_at) '
      'VALUES (\$1, \$2, \$3) ON CONFLICT (event_id) DO NOTHING',
      parameters: <Object?>[eventId, type, processedAt.toUtc()],
    );
    return result.affectedRows > 0;
  }

  @override
  Future<void> releaseEvent(String eventId) async {
    await _pool.execute(
      'DELETE FROM stripe_events WHERE event_id = \$1',
      parameters: <Object?>[eventId],
    );
  }

  @override
  Future<StripeEventRecord?> eventOf(String eventId) async {
    final Result result = await _pool.execute(
      'SELECT event_id, event_type, processed_at FROM stripe_events '
      'WHERE event_id = \$1',
      parameters: <Object?>[eventId],
    );
    if (result.isEmpty) return null;
    final Map<String, dynamic> columns = result.first.toColumnMap();
    return StripeEventRecord(
      id: columns['event_id']! as String,
      type: columns['event_type']! as String,
      processedAt: (columns['processed_at']! as DateTime).toUtc(),
    );
  }
}
