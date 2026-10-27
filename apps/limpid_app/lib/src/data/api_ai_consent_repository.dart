import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/ai_consent_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';

/// Le dépôt du consentement qui lit l'API.
///
/// Les trois routes sont celles du serveur : `GET /v1/me/ai-consent` pour
/// l'état, `POST` pour donner l'accord, `DELETE` pour le retirer. Aucune
/// n'envoie de corps : la décision est celle du compte connecté.
final class ApiAiConsentRepository implements AiConsentRepository {
  /// Crée un dépôt sur le dessus de [client].
  const ApiAiConsentRepository({required this.client});

  /// Le client de l'API.
  final ApiClient client;

  /// La route de l'état du consentement.
  static const String path = '/v1/me/ai-consent';

  @override
  Future<AiConsentState> state() async {
    return _stateOf(await client.get(path));
  }

  @override
  Future<AiConsentState> grant() async {
    return _stateOf(await client.post(path));
  }

  @override
  Future<AiConsentState> revoke() async {
    return _stateOf(await client.delete(path));
  }

  /// L'état porté par la réponse du serveur.
  AiConsentState _stateOf(Object? payload) {
    if (payload is! Map<String, Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the consent of the account.',
      );
    }
    return AiConsentState(
      scope: payload['scope'] as String? ?? '',
      provider: payload['provider'] as String? ?? '',
      isGranted: payload['is_granted'] as bool? ?? false,
      requiresConsent: payload['requires_consent'] as bool? ?? true,
      grantedAt: _dateOf(payload['granted_at']),
      revokedAt: _dateOf(payload['revoked_at']),
    );
  }

  /// La date portée par la réponse, `null` quand il n'y en a pas.
  DateTime? _dateOf(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}
