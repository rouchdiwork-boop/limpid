import 'package:sqlite3/sqlite3.dart';

import 'sqlite_database.dart';
import 'sqlite_values.dart';
import 'stripe_event_database.dart';

/// L'implémentation SQLite du port [StripeEventDatabase].
///
/// La réservation d'un événement est portée par la base : l'insertion
/// `ON CONFLICT DO NOTHING` n'écrit la ligne que la première fois, et le
/// nombre de lignes touchées dit si la réservation est nouvelle.
///
/// Les horodatages sont les microsecondes depuis l'epoch Unix, la
/// convention du dialecte SQLite (D-29).
final class SqliteStripeEventDatabase implements StripeEventDatabase {
  /// Crée un port sur la base [database].
  const SqliteStripeEventDatabase(this._database);

  /// La base des événements traités.
  final SqliteDatabase _database;

  @override
  Future<bool> claimEvent({
    required String eventId,
    required String type,
    required DateTime processedAt,
  }) async {
    return _database.run(() {
      _database.connection.execute(
        'INSERT INTO stripe_events (event_id, event_type, processed_at) '
        'VALUES (?, ?, ?) ON CONFLICT (event_id) DO NOTHING',
        <Object?>[eventId, type, SqliteValues.encodeTimestamp(processedAt)],
      );
      // La base est sérialisée par `run` : aucune autre instruction ne
      // peut modifier le compteur entre l'écriture et sa lecture.
      return _database.connection.updatedRows > 0;
    });
  }

  @override
  Future<void> releaseEvent(String eventId) async {
    await _database.run(() {
      _database.connection.execute(
        'DELETE FROM stripe_events WHERE event_id = ?',
        <Object?>[eventId],
      );
    });
  }

  @override
  Future<StripeEventRecord?> eventOf(String eventId) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT event_id, event_type, processed_at FROM stripe_events '
        'WHERE event_id = ?',
        <Object?>[eventId],
      );
      if (result.isEmpty) return null;
      final Row row = result.first;
      return StripeEventRecord(
        id: row['event_id']! as String,
        type: row['event_type']! as String,
        processedAt: SqliteValues.decodeTimestamp(row['processed_at']),
      );
    });
  }
}
