import 'package:shelf/shelf.dart';

import '../auth/auth_middleware.dart';
import '../db/admin_database.dart';
import '../db/audit_entry.dart';
import '../db/feature_flag.dart';
import '../errors/app_exception.dart';
import '../http/pagination.dart';
import '../middleware/rate_limiter.dart';

/// The service of the back-office.
///
/// The service holds the rules of the administration: only an administrator
/// reaches it, the accounts are the ones the API knows, and every change of
/// an indicator is written in the journal of the audit trail.
///
/// The administrator is identified by a claim of the **verified** token:
/// the server never reads a role sent by the client, it reads the token it
/// has just verified. The claim is [adminClaim] and the value that grants
/// the administration is [adminRole].
final class AdminService {
  /// Creates a service on top of [database].
  const AdminService(this._database);

  final AdminDatabase _database;

  /// The claim of the verified token that carries the role of the account.
  ///
  /// In Supabase, the claim `role` carries the role of the application
  /// metadata: it is the value the identity provider signs, and therefore
  /// the only one the server may trust.
  static const String adminClaim = 'role';

  /// The value of [adminClaim] that grants the administration.
  static const String adminRole = 'admin';

  /// The maximum length of the key of an indicator.
  static const int maxFeatureFlagKeyLength = 64;

  /// The maximum length of the description of an indicator.
  static const int maxFeatureFlagDescriptionLength = 500;

  /// The shape of the key of an indicator.
  ///
  /// The key travels in the path of the request: it is a technical
  /// identifier, made of lower case letters, digits, dots, dashes and
  /// underscores.
  static final RegExp _featureFlagKeyPattern = RegExp(
    r'^[a-z0-9][a-z0-9._-]*$',
  );

  /// The administrator of the request.
  ///
  /// Throws an [UnauthorizedException] when the request is anonymous and a
  /// [ForbiddenException] when the caller is not an administrator.
  static AuthContext requireAdmin(Request request) {
    final AuthContext? auth = authOf(request);
    if (auth == null) {
      throw const UnauthorizedException(
        message:
            'Une authentification est requise pour accéder à cette ressource.',
      );
    }
    if (auth.stringClaim(adminClaim) != adminRole) {
      throw const ForbiddenException(
        message: 'Cette ressource est réservée à l\'administration.',
      );
    }
    return auth;
  }

  /// The accounts the API knows, with their formula and their usage.
  ///
  /// The accounts live in the identity provider: the list is the one the
  /// API can build from its own tables, and it never claims to be the list
  /// of the people who registered.
  Future<AccountPage> listAccounts({
    required Request request,
    required PageRequest page,
  }) async {
    requireAdmin(request);
    return _database.listAccounts(limit: page.limit, cursor: page.cursor);
  }

  /// The account of [userId].
  ///
  /// Throws a [NotFoundException] when the API does not know the account.
  Future<AdminAccount> findAccount({
    required Request request,
    required String userId,
  }) async {
    requireAdmin(request);
    final AdminAccount? account = await _database.findAccount(userId);
    if (account == null) {
      throw const NotFoundException(
        message: "Ce compte n'existe pas ou n'est plus accessible.",
      );
    }
    return account;
  }

  /// The indicators of functionality and their state.
  Future<List<FeatureFlag>> listFeatureFlags({required Request request}) async {
    requireAdmin(request);
    return _database.listFeatureFlags();
  }

  /// Activates or deactivates the indicator [key].
  ///
  /// The indicator is created when it does not exist yet. The change is
  /// written in the journal of the audit trail: an administrator turning a
  /// functionality on or off is a sensitive action.
  Future<FeatureFlag> setFeatureFlag({
    required Request request,
    required String key,
    required bool isEnabled,
    required String? description,
  }) async {
    final AuthContext admin = requireAdmin(request);
    final String normalized = _validatedKey(key);
    final FeatureFlag flag = await _database.setFeatureFlag(
      key: normalized,
      isEnabled: isEnabled,
      description: description,
      updatedBy: admin.userId,
    );
    await _database.audit.record(
      AuditEntry(
        userId: admin.userId,
        action: 'admin.feature_flag_changed',
        targetType: 'feature_flag',
        targetId: normalized,
        metadata: <String, Object?>{'enabled': isEnabled},
        ip: clientIpOf(request),
      ),
    );
    return flag;
  }

  /// The key of an indicator, once it has been checked.
  ///
  /// Throws a [ValidationException] when the key does not have the expected
  /// shape: the key is written in the base, and a malformed one would be a
  /// mistake of the administrator.
  static String _validatedKey(String key) {
    if (key.isEmpty ||
        key.length > maxFeatureFlagKeyLength ||
        !_featureFlagKeyPattern.hasMatch(key)) {
      throw const ValidationException(
        field: 'key',
        message:
            'La clé d\'un indicateur ne contient que des lettres '
            'minuscules, des chiffres, des points, des tirets et des '
            'tirets bas.',
      );
    }
    return key;
  }
}
