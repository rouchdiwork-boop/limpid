import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';

/// Le nombre de chiffres d'un code, quand le serveur n'en dit rien.
///
/// Le serveur publie toujours le nombre de chiffres : la valeur n'est qu'un
/// filet de sécurité pour une réponse incomplète.
const int defaultTotpDigits = 6;

/// La durée d'un pas de l'horloge, quand le serveur n'en dit rien.
const int defaultTotpPeriodSeconds = 30;

/// La durée de vie d'une preuve, quand le serveur n'en dit rien.
const Duration defaultTwoFactorProofLifetime = Duration(minutes: 15);

/// La double authentification de l'auteur, servie par l'API.
///
/// Les cinq routes de `/v1/me/2fa` décrivent le cycle de vie du second
/// facteur : l'état du compte, l'inscription, la confirmation, la
/// vérification et la désactivation.
///
/// Le dépôt ne laisse jamais sortir une exception brute : un échec est
/// toujours l'un des types de `domain/errors.dart`.
final class ApiTwoFactorRepository implements TwoFactorRepository {
  /// Crée un dépôt sur le dessus de [client].
  const ApiTwoFactorRepository({required this.client});

  /// Le client de l'API.
  final ApiClient client;

  @override
  Future<TwoFactorStatus> status() async {
    final Object? payload = await client.get('/v1/me/2fa');
    final Map<String, Object?> data = _objectOf(payload);
    return TwoFactorStatus(
      enrolled: _boolOf(data['enrolled']),
      enabled: _boolOf(data['enabled']),
      required: _boolOf(data['required']),
    );
  }

  @override
  Future<TwoFactorEnrollment> enroll() async {
    final Object? payload = await client.post('/v1/me/2fa/enroll');
    final Map<String, Object?> data = _objectOf(payload);
    return TwoFactorEnrollment(
      secret: _stringOf(data['secret']) ?? '',
      otpauthUrl: _stringOf(data['otpauth_url']) ?? '',
      digits: _intOf(data['digits']) ?? defaultTotpDigits,
      periodSeconds: _intOf(data['period_seconds']) ?? defaultTotpPeriodSeconds,
    );
  }

  @override
  Future<List<String>> confirm({required String code}) async {
    final Object? payload = await client.post(
      '/v1/me/2fa/confirm',
      body: <String, Object?>{'code': code},
    );
    final Map<String, Object?> data = _objectOf(payload);
    final Object? codes = data['recovery_codes'];
    if (codes is! List<dynamic>) {
      throw const ApiMalformedResponseException(
        'The API did not return the recovery codes.',
      );
    }
    final List<String> recovery = <String>[
      for (final Object? item in codes)
        if (item is String) item,
    ];
    return List<String>.unmodifiable(recovery);
  }

  @override
  Future<TwoFactorProof> verify({required String code}) async {
    final Object? payload = await client.post(
      '/v1/me/2fa/verify',
      body: <String, Object?>{'code': code},
    );
    final Map<String, Object?> data = _objectOf(payload);
    final String proof = _stringOf(data['proof']) ?? '';
    if (proof.isEmpty) {
      throw const ApiMalformedResponseException(
        'The API did not return the proof of the second factor.',
      );
    }
    return TwoFactorProof(
      proof: proof,
      expiresAt:
          _momentOf(data['expires_at']) ??
          DateTime.now().toUtc().add(defaultTwoFactorProofLifetime),
      method:
          TwoFactorMethod.fromKey(_stringOf(data['method']) ?? '') ??
          TwoFactorMethod.totp,
    );
  }

  @override
  Future<void> disable() async {
    await client.delete('/v1/me/2fa');
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

  static int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
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
