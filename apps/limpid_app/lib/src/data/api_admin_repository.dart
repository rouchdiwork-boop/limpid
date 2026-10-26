import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/admin_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';

/// Le back-office, servi par l'API.
///
/// Les trois lectures du port — les comptes, le détail d'un compte et les
/// indicateurs — reprennent les routes que l'API réserve à
/// l'administrateur. Le refus du serveur n'est pas une panne : il remonte
/// tel quel, et l'écran le lit comme un refus d'accès.
///
/// La quatrième route, l'activation d'un indicateur, est en `PUT` : le
/// client de l'API porte la demande, avec le jeton de session et la preuve
/// du second facteur.
final class ApiAdminRepository implements AdminRepository {
  /// Crée un dépôt sur le dessus de [client].
  const ApiAdminRepository({required this.client});

  /// Le client de l'API.
  final ApiClient client;

  @override
  Future<List<AdminAccount>> accounts() async {
    final Object? payload = await client.get('/v1/admin/users');
    if (payload is! List<Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the list of the accounts.',
      );
    }
    return List<AdminAccount>.unmodifiable(payload.map(_accountOf));
  }

  @override
  Future<AdminAccount> account(String userId) async {
    final Object? payload = await client.get(
      '/v1/admin/users/${Uri.encodeComponent(userId)}',
    );
    return _accountOf(payload);
  }

  @override
  Future<List<AdminFeatureFlag>> featureFlags() async {
    final Object? payload = await client.get('/v1/admin/feature-flags');
    if (payload is! List<Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the list of the feature flags.',
      );
    }
    return List<AdminFeatureFlag>.unmodifiable(payload.map(_flagOf));
  }

  @override
  Future<AdminFeatureFlag> setFeatureFlag(
    String key, {
    required bool isEnabled,
  }) async {
    final Object? payload = await client.put(
      '/v1/admin/feature-flags/${Uri.encodeComponent(key)}',
      body: <String, Object?>{'enabled': isEnabled},
    );
    return _flagOf(payload);
  }

  /// Le compte porté par la réponse du serveur.
  static AdminAccount _accountOf(Object? payload) {
    final Map<String, Object?> json = _objectOf(payload, 'the account');
    return AdminAccount(
      userId: _stringOf(json['user_id']) ?? '',
      email: _stringOf(json['email']),
      plan: _stringOf(json['plan']),
      projectCount: _intOf(json['project_count']) ?? 0,
      collaborationCount: _intOf(json['collaboration_count']) ?? 0,
      commentCount: _intOf(json['comment_count']) ?? 0,
      operationCount: _intOf(json['operation_count']) ?? 0,
      lastActivityAt: _momentOf(json['last_activity_at']),
      isPurged: _boolOf(json['is_purged']) ?? false,
    );
  }

  /// L'indicateur porté par la réponse du serveur.
  static AdminFeatureFlag _flagOf(Object? payload) {
    final Map<String, Object?> json = _objectOf(payload, 'the feature flag');
    return AdminFeatureFlag(
      key: _stringOf(json['key']) ?? '',
      isEnabled: _boolOf(json['is_enabled']) ?? false,
      description: _stringOf(json['description']) ?? '',
      updatedAt: _momentOf(json['updated_at']) ?? DateTime.now().toUtc(),
      updatedBy: _stringOf(json['updated_by']) ?? '',
    );
  }

  /// Un objet JSON, ou une réponse refusée.
  static Map<String, Object?> _objectOf(Object? value, String what) {
    if (value is Map<String, Object?>) return value;
    throw ApiMalformedResponseException('The API did not return $what.');
  }

  /// Un texte, `null` quand le serveur n'en envoie pas.
  static String? _stringOf(Object? value) {
    if (value is String) return value;
    return null;
  }

  /// Un nombre, `null` quand le serveur n'en envoie pas.
  static int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  /// Un booléen, `null` quand le serveur n'en envoie pas.
  static bool? _boolOf(Object? value) {
    if (value is bool) return value;
    return null;
  }

  /// Un instant, `null` quand le serveur n'en envoie pas.
  static DateTime? _momentOf(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
