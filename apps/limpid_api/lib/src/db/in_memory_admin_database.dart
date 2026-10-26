import '../http/pagination.dart';
import 'admin_database.dart';
import 'audit_log.dart';
import 'feature_flag.dart';
import 'in_memory_admin_audit_log.dart';

/// An in-memory [AdminDatabase], used by the test suite.
///
/// The store keeps the same invariants as the SQL implementations: the
/// accounts are deduplicated, the page is walked with the opaque cursor,
/// and the indicators are created on the first change.
final class InMemoryAdminDatabase implements AdminDatabase {
  /// Creates an empty back-office.
  InMemoryAdminDatabase() : _audit = InMemoryAdminAuditLog();

  final InMemoryAdminAuditLog _audit;

  final Map<String, AdminAccount> _accounts = <String, AdminAccount>{};
  final Map<String, String> _plans = <String, String>{};
  final Map<String, FeatureFlag> _flags = <String, FeatureFlag>{};

  /// The moment the accounts without activity are sorted on.
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  @override
  AuditLog get audit => _audit;

  /// The accounts the database knows, by identifier.
  Map<String, AdminAccount> get accounts =>
      Map<String, AdminAccount>.unmodifiable(_accounts);

  /// Adds an account the database knows, with its usage.
  void addAccount({
    required String userId,
    int projectCount = 0,
    int collaborationCount = 0,
    int commentCount = 0,
    int operationCount = 0,
    DateTime? lastActivityAt,
    bool isPurged = false,
  }) {
    _accounts[userId] = AdminAccount(
      userId: userId,
      plan: null,
      projectCount: projectCount,
      collaborationCount: collaborationCount,
      commentCount: commentCount,
      operationCount: operationCount,
      lastActivityAt: lastActivityAt,
      isPurged: isPurged,
    );
  }

  /// Assigns the formula [plan] to the account [userId].
  void assignPlan({required String userId, required String plan}) {
    _plans[userId] = plan;
  }

  /// Adds the indicator [flag] to the database.
  void addFeatureFlag(FeatureFlag flag) {
    _flags[flag.key] = flag;
  }

  @override
  Future<AccountPage> listAccounts({
    required int limit,
    required String? cursor,
  }) async {
    final List<AdminAccount> visible = _accounts.values.toList(growable: false)
      ..sort(_compareAccounts);
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<AdminAccount> afterCursor = decoded == null
        ? visible
        : visible
              .where((AdminAccount account) => _isAfter(account, decoded))
              .toList(growable: false);
    final List<AdminAccount> items = afterCursor
        .take(limit)
        .toList(growable: false);
    final bool hasMore = afterCursor.length > items.length;
    final String? nextCursor = hasMore && items.isNotEmpty
        ? PageCursor.encode(_sortKeyOf(items.last), items.last.userId)
        : null;

    return AccountPage(
      items: List<AdminAccount>.unmodifiable(
        items.map(
          (AdminAccount account) =>
              account.copyWith(plan: _plans[account.userId]),
        ),
      ),
      total: visible.length,
      nextCursor: nextCursor,
    );
  }

  @override
  Future<AdminAccount?> findAccount(String userId) async {
    final AdminAccount? account = _accounts[userId];
    if (account == null) return null;
    return account.copyWith(plan: _plans[userId]);
  }

  @override
  Future<List<FeatureFlag>> listFeatureFlags() async {
    final List<FeatureFlag> flags = _flags.values.toList(growable: false)
      ..sort(
        (FeatureFlag left, FeatureFlag right) => left.key.compareTo(right.key),
      );
    return List<FeatureFlag>.unmodifiable(flags);
  }

  @override
  Future<FeatureFlag?> findFeatureFlag(String key) async {
    return _flags[key];
  }

  @override
  Future<FeatureFlag> setFeatureFlag({
    required String key,
    required bool isEnabled,
    required String? description,
    required String updatedBy,
  }) async {
    final FeatureFlag? existing = _flags[key];
    final FeatureFlag flag = FeatureFlag(
      key: key,
      isEnabled: isEnabled,
      description: description ?? existing?.description ?? '',
      updatedAt: DateTime.now().toUtc(),
      updatedBy: updatedBy,
    );
    _flags[key] = flag;
    return flag;
  }

  /// The sort key of an account, the epoch when it has no activity.
  static String _sortKeyOf(AdminAccount account) {
    return (account.lastActivityAt ?? _epoch).toUtc().toIso8601String();
  }

  /// The most recently active account comes first, the identifier breaks the
  /// ties.
  static int _compareAccounts(AdminAccount left, AdminAccount right) {
    final DateTime leftMoment = left.lastActivityAt ?? _epoch;
    final DateTime rightMoment = right.lastActivityAt ?? _epoch;
    final int byDate = rightMoment.compareTo(leftMoment);
    if (byDate != 0) return byDate;
    return left.userId.compareTo(right.userId);
  }

  /// Whether the account comes after the cursor.
  static bool _isAfter(AdminAccount account, PageCursorValue cursor) {
    final DateTime cursorMoment = DateTime.parse(cursor.updatedAt);
    final DateTime moment = account.lastActivityAt ?? _epoch;
    final int byDate = cursorMoment.compareTo(moment);
    if (byDate != 0) return byDate > 0;
    return account.userId.compareTo(cursor.id) > 0;
  }
}
