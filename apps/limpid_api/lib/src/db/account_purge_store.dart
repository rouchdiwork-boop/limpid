import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:sqlite3/sqlite3.dart';

import 'audit_entry.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// Le résultat de la purge d'un compte.
final class AccountPurgeOutcome {
  /// Crée un résultat.
  const AccountPurgeOutcome({
    required this.userId,
    required this.projectsDeleted,
    required this.operationsDeleted,
    required this.collaborationsDeleted,
    required this.messagesDeleted,
    required this.personalRowsDeleted,
    required this.purged,
  });

  /// Le compte dont la donnée a été effacée.
  final String userId;

  /// Le nombre de livres du compte qui ont été effacés.
  final int projectsDeleted;

  /// Le nombre d'opérations du journal de synchronisation qui ont été
  /// effacées.
  final int operationsDeleted;

  /// Le nombre de collaborations du compte qui ont été effacées.
  final int collaborationsDeleted;

  /// Le nombre de messages du compte qui ont été effacés.
  final int messagesDeleted;

  /// Le nombre de lignes de l'auteur effacées par la purge, dans toutes les
  /// tables.
  ///
  /// Le compteur couvre tout le schéma : le secret de la double
  /// authentification, la formule du compte, la consommation, les clés de
  /// l'API, les points de rappel et leurs livraisons, les équipes, les
  /// publications Amazon, et les livres eux-mêmes. Les lignes dont
  /// l'identifiant de l'auteur a été vidé comptent aussi.
  final int personalRowsDeleted;

  /// Si ce worker a effectué la purge.
  ///
  /// La purge est refusée quand le compte était déjà purgé : le registre
  /// des purges porte déjà sa trace, et une seconde purge ne changerait
  /// rien.
  final bool purged;
}

/// Le port de persistance de la purge des comptes.
///
/// Le port traverse deux tables : le journal d'audit, qui porte les demandes
/// de suppression, et le registre des purges, qui porte les comptes effacés.
/// Il n'écrit jamais dans le journal et ne le vide jamais : la piste d'audit
/// survit à la donnée qu'elle décrit (D-19).
abstract interface class AccountPurgeStore {
  /// Les entrées du journal d'audit portant [action], les plus anciennes
  /// d'abord.
  ///
  /// Le journal est la source de vérité des suppressions en attente : la
  /// demande d'un auteur est une marque dans la piste d'audit, et la purge
  /// la lit pour savoir quels comptes doivent être vidés, et quand.
  Future<List<AuditEntry>> journalEntries({
    required String action,
    required int limit,
  });

  /// Efface la donnée de [userId] pour de bon.
  ///
  /// L'effacement couvre toutes les tables déclarées comme données
  /// personnelles : les livres que le compte possède, les opérations du
  /// journal de synchronisation qui leur appartiennent, les collaborations,
  /// les messages, le secret de la double authentification et les codes de
  /// récupération, la formule du compte, sa consommation, les clés d'API,
  /// les points de rappel et leurs livraisons, les équipes, et les
  /// publications Amazon. Les opérations de l'auteur sur le livre d'un autre
  /// sont effacées aussi : c'est la donnée personnelle de l'auteur, pas le
  /// manuscrit du co-auteur.
  ///
  /// Les tables qui sont gardées sont déclarées aussi, avec la raison de la
  /// décision : la piste d'audit, le registre des purges et la trace des
  /// suppressions des tiers sont conservés (D-19), et les identifiants de
  /// l'administrateur qui a changé un indicateur sont vidés.
  ///
  /// L'appel est idempotent : un compte déjà purgé est laissé intact, et
  /// les lignes écrites après sa purge survivent.
  Future<AccountPurgeOutcome> purge({
    required String userId,
    String? email,
    required DateTime requestedAt,
    required DateTime scheduledFor,
    required DateTime purgedAt,
    required String workerId,
  });
}

/// Le port SQL de la purge.
///
/// Le dialecte est confiné aux adaptateurs : SQLite et Postgres diffèrent
/// sur les marqueurs de position, sur les horodatages et sur les documents
/// JSON (D-29). Le SQL est écrit une seule fois, avec les marqueurs de
/// position de SQLite.
abstract interface class AccountPurgeDatabase {
  /// Réécrit les marqueurs de position `?` de [sql] pour le moteur.
  String rewrite(String sql);

  /// Exécute la requête [sql] et rend ses lignes.
  Future<List<Map<String, Object?>>> query(String sql, List<Object?> args);

  /// Exécute [statements] dans une seule transaction.
  ///
  /// La méthode rend le nombre de lignes que chaque instruction a
  /// touchées, dans l'ordre des instructions : la purge le lit pour
  /// rapporter ce qu'elle a effacé.
  Future<List<int>> transaction(List<(String, List<Object?>)> statements);

  /// Encode un horodatage pour le moteur.
  Object? encodeTimestamp(DateTime? value);

  /// Décode un horodatage lu dans le moteur.
  DateTime? decodeTimestamp(Object? value);

  /// Décode un document JSON lu dans le moteur.
  Map<String, dynamic> decodeJson(Object? value);
}

/// L'adaptateur SQLite de la purge.
///
/// Les horodatages sont les microsecondes depuis l'époque Unix et les
/// documents JSON sont textuels : la convention du dialecte SQLite (voir
/// `SqliteValues`).
final class SqliteAccountPurgeDatabase implements AccountPurgeDatabase {
  /// Crée un adaptateur sur [database].
  const SqliteAccountPurgeDatabase(this._database);

  /// La base de données de l'API.
  final SqliteDatabase _database;

  @override
  String rewrite(String sql) => sql;

  @override
  Future<List<Map<String, Object?>>> query(String sql, List<Object?> args) =>
      _database.run(() {
        final ResultSet result = _database.connection.select(sql, args);
        return result
            .map((Row row) => Map<String, Object?>.from(row))
            .toList(growable: false);
      });

  @override
  Future<List<int>> transaction(List<(String, List<Object?>)> statements) =>
      _database.transaction(() {
        final List<int> counts = <int>[];
        for (final (String sql, List<Object?> args) in statements) {
          _database.connection.execute(sql, args);
          counts.add(_database.connection.updatedRows);
        }
        return counts;
      });

  @override
  Object? encodeTimestamp(DateTime? value) =>
      value == null ? null : SqliteValues.encodeTimestamp(value);

  @override
  DateTime? decodeTimestamp(Object? value) =>
      value == null ? null : SqliteValues.decodeTimestamp(value);

  @override
  Map<String, dynamic> decodeJson(Object? value) =>
      SqliteValues.decodeJson(value);
}

/// L'adaptateur Postgres de la purge.
///
/// Les horodatages sont envoyés en `TIMESTAMPTZ` et les documents JSON en
/// `JSONB` ; les marqueurs de position du SQL sont réécrits sous la forme
/// indexée du protocole (`$1`, `$2`…).
final class PostgresAccountPurgeDatabase implements AccountPurgeDatabase {
  /// Crée un adaptateur sur [pool].
  const PostgresAccountPurgeDatabase(this._pool);

  /// Le pool de l'API.
  final Pool<Object?> _pool;

  @override
  String rewrite(String sql) {
    var index = 0;
    return sql.replaceAllMapped(RegExp(r'\?'), (Match _) => '\$${++index}');
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> args,
  ) async {
    final Result result = await _pool.execute(rewrite(sql), parameters: args);
    return result
        .map((ResultRow row) => Map<String, Object?>.from(row.toColumnMap()))
        .toList(growable: false);
  }

  @override
  Future<List<int>> transaction(
    List<(String, List<Object?>)> statements,
  ) async {
    return _pool.runTx((TxSession session) async {
      final List<int> counts = <int>[];
      for (final (String sql, List<Object?> args) in statements) {
        final Result result = await session.execute(
          rewrite(sql),
          parameters: args,
        );
        counts.add(result.affectedRows);
      }
      return counts;
    });
  }

  @override
  Object? encodeTimestamp(DateTime? value) => value?.toUtc();

  @override
  DateTime? decodeTimestamp(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
  }

  @override
  Map<String, dynamic> decodeJson(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      final Object? decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return const <String, dynamic>{};
  }
}
