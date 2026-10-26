import 'audit_log.dart';
import 'feature_flag.dart';

/// An account, as the back-office knows it.
///
/// The accounts live in the identity provider of Supabase: the API only
/// knows the identifiers it met in its own tables. The record therefore
/// describes what the API knows — the manuscripts of the account, its
/// collaborations and its activity — and not a profile of the person.
///
/// A field is `null` when the database does not know it. The formula of an
/// account is unknown until the module that owns the plans writes it.
final class AdminAccount {
  /// Creates an account.
  const AdminAccount({
    required this.userId,
    required this.plan,
    required this.projectCount,
    required this.collaborationCount,
    required this.commentCount,
    required this.operationCount,
    required this.lastActivityAt,
    required this.isPurged,
  });

  /// The identifier of the account.
  final String userId;

  /// The formula of the account, `null` when the server does not know it.
  final String? plan;

  /// The number of projects the account owns.
  final int projectCount;

  /// The number of projects the account collaborates on.
  final int collaborationCount;

  /// The number of messages the account wrote.
  final int commentCount;

  /// The number of operations the account pushed.
  final int operationCount;

  /// The moment of the last activity of the account.
  final DateTime? lastActivityAt;

  /// Whether the data of the account was erased for good.
  final bool isPurged;

  /// A copy of the account with the given fields replaced.
  ///
  /// The absent fields keep the value they had: the copy never loses a
  /// value it was not asked to change.
  AdminAccount copyWith({String? plan, bool? isPurged}) {
    return AdminAccount(
      userId: userId,
      plan: plan ?? this.plan,
      projectCount: projectCount,
      collaborationCount: collaborationCount,
      commentCount: commentCount,
      operationCount: operationCount,
      lastActivityAt: lastActivityAt,
      isPurged: isPurged ?? this.isPurged,
    );
  }
}

/// A page of accounts.
final class AccountPage {
  /// Creates a page.
  const AccountPage({
    required this.items,
    required this.total,
    required this.nextCursor,
  });

  /// The accounts of the page.
  final List<AdminAccount> items;

  /// The total number of accounts the database knows.
  final int total;

  /// The cursor pointing at the next page, `null` when the page is the last
  /// one.
  final String? nextCursor;
}

/// The persistence port of the back-office.
///
/// The port reads the accounts the API knows and holds the indicators of
/// functionality. It also carries the journal of the audit trail: the
/// activation of an indicator is a sensitive action, and the entry is
/// written in the same journal as the other sensitive actions of the API.
abstract interface class AdminDatabase {
  /// The journal of the audit trail.
  AuditLog get audit;

  /// Lists the accounts the database knows, the most recently active first.
  ///
  /// The page is walked with the opaque cursor of the pagination: the
  /// [cursor] points at the account the page starts after.
  Future<AccountPage> listAccounts({
    required int limit,
    required String? cursor,
  });

  /// The account of [userId], `null` when the database does not know it.
  Future<AdminAccount?> findAccount(String userId);

  /// The indicators of functionality, by key.
  Future<List<FeatureFlag>> listFeatureFlags();

  /// The indicator [key], `null` when it does not exist.
  Future<FeatureFlag?> findFeatureFlag(String key);

  /// Activates or deactivates the indicator [key] and answers its new
  /// state.
  ///
  /// The indicator is created when it does not exist yet. The description
  /// is only written when it is given: an absent description keeps the one
  /// the indicator already had.
  Future<FeatureFlag> setFeatureFlag({
    required String key,
    required bool isEnabled,
    required String? description,
    required String updatedBy,
  });
}
