import 'package:limpid_core/limpid_core.dart';
import 'package:postgres/postgres.dart';
import 'package:sqlite3/sqlite3.dart';

import '../services/plan_catalog.dart';
import 'quota_database.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';

/// Le port SQL des quotas.
///
/// Le dialecte est confiné aux adaptateurs : SQLite et Postgres diffèrent
/// sur les placeholders, sur les horodatages et sur la syntaxe de la mise à
/// jour d'une ligne existante. Le SQL lui-même est écrit une seule fois,
/// avec les placeholders `?` de SQLite.
abstract interface class QuotaSqlPort {
  /// Réécrit les placeholders `?` de [sql] pour le moteur.
  String rewrite(String sql);

  /// Exécute la requête [sql] et renvoie ses lignes.
  Future<List<Map<String, Object?>>> query(String sql, List<Object?> args);

  /// Exécute l'instruction [sql].
  Future<void> execute(String sql, List<Object?> args);

  /// Encode un horodatage pour le moteur.
  Object? encodeTimestamp(DateTime? value);

  /// Décode un horodatage lu dans le moteur.
  DateTime? decodeTimestamp(Object? value);
}

/// La base commune des quotas SQL.
///
/// Le port couvre deux tables : la formule affectée au compte et les
/// compteurs de consommation. Toutes les écritures sont paramétrées :
/// aucune valeur n'atteint le moteur par concaténation de chaînes.
abstract class SqlQuotaDatabase implements QuotaDatabase {
  /// Crée la base sur top du port [port].
  SqlQuotaDatabase(this._port);

  /// Le port SQL du moteur.
  final QuotaSqlPort _port;

  /// La requête lisant la formule d'un compte.
  static const String _selectPlan =
      'SELECT plan, billing_period, trial_ends_at, trial_consumed_at, '
      'period_started_at, period_ends_at FROM account_plans WHERE user_id = ?';

  /// L'instruction affectant une formule à un compte.
  ///
  /// La ligne existante est remplacée : un compte porte une seule formule à
  /// la fois, et un changement de formule ne laisse jamais deux affectations
  /// concurrentes.
  static const String _assignPlan =
      'INSERT INTO account_plans (user_id, plan, billing_period, '
      'trial_ends_at, trial_consumed_at, period_started_at, period_ends_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (user_id) DO UPDATE SET '
      'plan = excluded.plan, '
      'billing_period = excluded.billing_period, '
      'trial_ends_at = excluded.trial_ends_at, '
      'trial_consumed_at = excluded.trial_consumed_at, '
      'period_started_at = excluded.period_started_at, '
      'period_ends_at = excluded.period_ends_at';

  /// La requête lisant les consommations d'un compte.
  static const String _selectUsages =
      'SELECT feature, period_key, quantity FROM quota_usage '
      'WHERE user_id = ? ORDER BY period_key ASC, feature ASC';

  /// L'instruction consommant une unité d'une fonctionnalité.
  ///
  /// L'incrément est porté par la base : deux écritures concurrentes ne
  /// perdent aucune unité, et le compteur n'est jamais réécrit à partir d'une
  /// valeur lue ailleurs.
  static const String _consume =
      'INSERT INTO quota_usage (user_id, feature, period_key, quantity) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT (user_id, feature, period_key) DO UPDATE SET '
      'quantity = quantity + excluded.quantity';

  @override
  Future<AccountPlan?> planOf(String userId) async {
    final List<Map<String, Object?>> rows = await _port.query(
      _selectPlan,
      <Object?>[userId],
    );
    if (rows.isEmpty) return null;
    return _readPlan(userId, rows.first);
  }

  @override
  Future<void> assignPlan(AccountPlan plan) async {
    await _port.execute(_assignPlan, <Object?>[
      plan.userId,
      plan.plan.name,
      plan.period.name,
      _port.encodeTimestamp(plan.trialEndsAt),
      _port.encodeTimestamp(plan.trialConsumedAt),
      _port.encodeTimestamp(plan.periodStartedAt),
      _port.encodeTimestamp(plan.periodEndsAt),
    ]);
  }

  @override
  Future<int> usageOf({
    required String userId,
    required QuotaFeature feature,
    required String periodKey,
  }) async {
    final List<Map<String, Object?>> rows = await _port.query(
      'SELECT quantity FROM quota_usage WHERE user_id = ? AND feature = ? '
      'AND period_key = ?',
      <Object?>[userId, feature.key, periodKey],
    );
    if (rows.isEmpty) return 0;
    final Object? raw = rows.first['quantity'];
    return raw is int ? raw : 0;
  }

  @override
  Future<List<QuotaUsage>> usagesOf(String userId) async {
    final List<Map<String, Object?>> rows = await _port.query(
      _selectUsages,
      <Object?>[userId],
    );
    return List<QuotaUsage>.unmodifiable(
      rows.map(
        (Map<String, Object?> row) => QuotaUsage(
          userId: userId,
          feature: _readFeature(row['feature']),
          periodKey: _readText(row, 'period_key'),
          quantity: _readQuantity(row['quantity']),
        ),
      ),
    );
  }

  @override
  Future<void> consume({
    required String userId,
    required QuotaFeature feature,
    required String periodKey,
    int amount = 1,
  }) async {
    await _port.execute(_consume, <Object?>[
      userId,
      feature.key,
      periodKey,
      amount,
    ]);
  }

  /// Lit l'affectation de formule d'une ligne.
  AccountPlan _readPlan(String userId, Map<String, Object?> row) {
    final String raw = _readText(row, 'plan');
    final SubscriptionPlan? plan = _readPlanName(raw);
    if (plan == null) {
      throw FormatException('Unknown plan: "$raw".');
    }
    final String rawPeriod = _readText(row, 'billing_period');
    final BillingPeriod? period = _readPeriodName(rawPeriod);
    if (period == null) {
      throw FormatException('Unknown billing period: "$rawPeriod".');
    }
    final DateTime? startedAt = _port.decodeTimestamp(row['period_started_at']);
    if (startedAt == null) {
      throw const FormatException('The plan has no period start date.');
    }
    return AccountPlan(
      userId: userId,
      plan: plan,
      period: period,
      periodStartedAt: startedAt,
      trialEndsAt: _port.decodeTimestamp(row['trial_ends_at']),
      trialConsumedAt: _port.decodeTimestamp(row['trial_consumed_at']),
      periodEndsAt: _port.decodeTimestamp(row['period_ends_at']),
    );
  }

  /// Lit le nom d'une formule, `null` quand il est inconnu.
  static SubscriptionPlan? _readPlanName(String raw) {
    for (final SubscriptionPlan plan in SubscriptionPlan.values) {
      if (plan.name == raw) return plan;
    }
    return null;
  }

  /// Lit le nom d'un cycle, `null` quand il est inconnu.
  static BillingPeriod? _readPeriodName(String raw) {
    for (final BillingPeriod period in BillingPeriod.values) {
      if (period.name == raw) return period;
    }
    return null;
  }

  /// Lit une fonctionnalité d'une ligne.
  QuotaFeature _readFeature(Object? raw) {
    final String key = raw is String ? raw : '';
    final QuotaFeature? feature = QuotaFeature.fromKey(key);
    if (feature == null) {
      throw FormatException('Unknown quota feature: "$key".');
    }
    return feature;
  }

  /// Lit une colonne de texte, vide quand elle est absente.
  static String _readText(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is String ? value : '';
  }

  /// Lit une colonne d'entier, zéro quand elle est absente.
  static int _readQuantity(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }
}

/// L'implémentation Postgres de [QuotaDatabase].
///
/// Les horodatages sont envoyés comme `TIMESTAMPTZ` et les placeholders sont
/// réécrits dans la forme indexée du protocole (`$1`, `$2`…).
final class PostgresQuotaDatabase extends SqlQuotaDatabase {
  /// Crée la base sur top du [pool].
  PostgresQuotaDatabase(Pool<Object?> pool) : super(_PostgresQuotaPort(pool));
}

/// L'implémentation SQLite de [QuotaDatabase].
///
/// Les horodatages sont les microsecondes depuis l'epoch Unix et les
/// placeholders sont ceux de SQLite (D-29).
final class SqliteQuotaDatabase extends SqlQuotaDatabase {
  /// Crée la base sur top de la [database].
  SqliteQuotaDatabase(SqliteDatabase database)
    : super(_SqliteQuotaPort(database));
}

/// Le port SQL du moteur Postgres.
final class _PostgresQuotaPort implements QuotaSqlPort {
  const _PostgresQuotaPort(this._pool);

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
  Future<void> execute(String sql, List<Object?> args) async {
    await _pool.execute(rewrite(sql), parameters: args);
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
}

/// Le port SQL du moteur SQLite.
final class _SqliteQuotaPort implements QuotaSqlPort {
  const _SqliteQuotaPort(this._database);

  final SqliteDatabase _database;

  @override
  String rewrite(String sql) => sql;

  @override
  Future<List<Map<String, Object?>>> query(String sql, List<Object?> args) {
    return _database.run(() {
      final ResultSet result = _database.connection.select(sql, args);
      return result
          .map((Row row) => Map<String, Object?>.from(row))
          .toList(growable: false);
    });
  }

  @override
  Future<void> execute(String sql, List<Object?> args) {
    return _database.run(() {
      _database.connection.execute(sql, args);
    });
  }

  @override
  Object? encodeTimestamp(DateTime? value) {
    return value == null ? null : SqliteValues.encodeTimestamp(value);
  }

  @override
  DateTime? decodeTimestamp(Object? value) {
    return value == null ? null : SqliteValues.decodeTimestamp(value);
  }
}
