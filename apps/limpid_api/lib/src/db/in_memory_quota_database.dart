import '../services/plan_catalog.dart';
import 'quota_database.dart';

/// Une consommation tenue en mémoire.
typedef _Usage = ({
  String userId,
  QuotaFeature feature,
  String periodKey,
  int quantity,
});

/// La base des quotas tenue en mémoire, utilisée par la suite de tests.
///
/// Elle respecte les mêmes invariants que l'implémentation SQL : un compte
/// porte une seule formule à la fois, et la consommation d'une
/// fonctionnalité est celle de la période demandée.
final class InMemoryQuotaDatabase implements QuotaDatabase {
  /// Crée une base vide.
  InMemoryQuotaDatabase();

  /// Les formules affectées, par compte.
  final Map<String, AccountPlan> _plans = <String, AccountPlan>{};

  /// Les consommations, par compte, fonctionnalité et période.
  final Map<String, _Usage> _usage = <String, _Usage>{};

  @override
  Future<AccountPlan?> planOf(String userId) async => _plans[userId];

  @override
  Future<void> assignPlan(AccountPlan plan) async {
    _plans[plan.userId] = plan;
  }

  @override
  Future<int> usageOf({
    required String userId,
    required QuotaFeature feature,
    required String periodKey,
  }) async {
    final _Usage? usage = _usage[_key(userId, feature, periodKey)];
    return usage?.quantity ?? 0;
  }

  @override
  Future<List<QuotaUsage>> usagesOf(String userId) async {
    final List<QuotaUsage> usages = <QuotaUsage>[];
    for (final MapEntry<String, _Usage> entry in _usage.entries) {
      final _Usage usage = entry.value;
      if (usage.userId != userId) continue;
      usages.add(
        QuotaUsage(
          userId: usage.userId,
          feature: usage.feature,
          periodKey: usage.periodKey,
          quantity: usage.quantity,
        ),
      );
    }
    usages.sort((QuotaUsage left, QuotaUsage right) {
      final int byPeriod = left.periodKey.compareTo(right.periodKey);
      if (byPeriod != 0) return byPeriod;
      return left.feature.key.compareTo(right.feature.key);
    });
    return List<QuotaUsage>.unmodifiable(usages);
  }

  @override
  Future<void> consume({
    required String userId,
    required QuotaFeature feature,
    required String periodKey,
    int amount = 1,
  }) async {
    final String key = _key(userId, feature, periodKey);
    final _Usage? usage = _usage[key];
    _usage[key] = (
      userId: userId,
      feature: feature,
      periodKey: periodKey,
      quantity: (usage?.quantity ?? 0) + amount,
    );
  }

  /// La clé d'une consommation.
  static String _key(String userId, QuotaFeature feature, String periodKey) =>
      '$userId|${feature.key}|$periodKey';
}
