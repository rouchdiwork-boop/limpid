import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/share_repository.dart';

/// Les partages en lecture, servis par l'API.
///
/// Les trois routes `/v1/projects/:projectId/shares`, `/v1/shares` et
/// `/v1/shares/:shareId` décrivent le cycle de vie des partages d'un
/// livre. Le jeton n'est rendu qu'à la création : le dépôt le rend à
/// l'écran, qui le montre une fois et ne le garde pas.
///
/// Le dépôt ne laisse jamais sortir une exception brute : un échec est
/// toujours l'un des types de `domain/errors.dart`.
final class ApiShareRepository implements ShareRepository {
  /// Crée un dépôt sur le dessus de [client].
  const ApiShareRepository({required this.client});

  /// Le client de l'API.
  final ApiClient client;

  @override
  Future<List<Share>> shares() async {
    final Object? payload = await client.get('/v1/shares');
    return _listOf(payload).map(_shareOf).toList(growable: false);
  }

  @override
  Future<CreatedShare> createShare({
    required String projectId,
    int? expiresInHours,
  }) async {
    final Object? payload = await client.post(
      '/v1/projects/$projectId/shares',
      body: <String, Object?>{'expires_in_hours': ?expiresInHours},
    );
    final Map<String, Object?> data = _objectOf(payload);
    return CreatedShare(
      share: _shareOf(data),
      token: _stringOf(data['token']) ?? '',
    );
  }

  @override
  Future<Share> revokeShare(String shareId) async {
    final Object? payload = await client.delete('/v1/shares/$shareId');
    return _shareOf(_objectOf(payload));
  }

  /// Le partage d'une réponse du serveur.
  static Share _shareOf(Map<String, Object?> data) {
    return Share(
      id: _stringOf(data['id']) ?? '',
      projectId: _stringOf(data['project_id']) ?? '',
      expiresAt: _momentOf(data['expires_at']) ?? DateTime.now().toUtc(),
      isRevoked: _boolOf(data['is_revoked']),
      createdAt: _momentOf(data['created_at']) ?? DateTime.now().toUtc(),
      revokedAt: _momentOf(data['revoked_at']),
    );
  }

  /// La charge d'une réponse, quand elle est une liste.
  static List<Map<String, Object?>> _listOf(Object? value) {
    if (value is! List<dynamic>) {
      throw const ApiMalformedResponseException(
        'The API did not return the expected list.',
      );
    }
    return <Map<String, Object?>>[
      for (final Object? item in value) _objectOf(item),
    ];
  }

  /// Le corps de la réponse, quand il est un objet.
  static Map<String, Object?> _objectOf(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const ApiMalformedResponseException(
      'The API did not return the expected payload.',
    );
  }

  static String? _stringOf(Object? value) {
    if (value is String) return value;
    return null;
  }

  static bool _boolOf(Object? value) {
    if (value is bool) return value;
    return false;
  }

  static DateTime? _momentOf(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
