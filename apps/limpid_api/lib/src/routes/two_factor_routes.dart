import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/two_factor_database.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/two_factor_models.dart';
import '../services/two_factor_service.dart';

/// La longueur maximale d'un code envoyé par le client.
///
/// La valeur couvre un code TOTP et un code de récupération.
const int maxTwoFactorCodeLength = 64;

/// Le nombre de vérifications tolérées d'affilée.
///
/// Un code TOTP ne compte que six chiffres : sans seau propre, un mot de
/// passe volé suffirait à essayer toutes les combinaisons. Le seau est
/// serré : cinq vérifications d'affilée, puis une toutes les dix secondes.
const int twoFactorRateLimitCapacity = 5;

/// Le nombre de vérifications regagnées par seconde.
const double twoFactorRateLimitRefillPerSecond = 0.1;

/// Enregistre les routes de la double authentification.
///
/// Les quatre routes décrivent le cycle de vie du second facteur :
/// l'inscription rend l'URL du secret, la confirmation active la double
/// authentification et rend les codes de récupération une seule fois, la
/// vérification prouve le second facteur et la suppression désactive la
/// double authentification.
///
/// [planOf] lit la formule du compte : elle dit si la double
/// authentification est obligatoire. Sans cette lecture, chaque compte est
/// traité comme un compte gratuit.
void registerTwoFactorRoutes(
  Router router,
  TwoFactorDatabase database,
  AppConfig config, {
  PlanLookup? planOf,
}) {
  final TwoFactorService service = TwoFactorService(
    database: database,
    planOf: planOf ?? _freePlan,
  );

  // La vérification d'un code est l'attaque la plus rentable qui soit : le
  // seau lui est propre, bien plus serré que le seau général de l'API.
  final TokenBucketRateLimiter limiter = TokenBucketRateLimiter(
    capacity: twoFactorRateLimitCapacity,
    refillPerSecond: twoFactorRateLimitRefillPerSecond,
  );

  router.get('/v1/me/2fa', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final TwoFactorState state = await service.stateOf(auth.userId);
    return ApiResponse.ok(state.toJson());
  });

  router.post('/v1/me/2fa/enroll', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final TwoFactorEnrollment enrollment = await service.enroll(
      userId: auth.userId,
      email: auth.email.isEmpty ? auth.userId : auth.email,
    );
    return ApiResponse.ok(enrollment.toJson());
  });

  router.post(
    '/v1/me/2fa/confirm',
    rateLimitMiddleware(
      limiter: limiter,
      scope: 'two_factor',
      applies: (Request request) => true,
    )((Request request) async {
      final AuthContext auth = requireAuthContext(request);
      final JsonBody body = await JsonBody.fromRequest(
        request,
        maxBytes: config.maxBodyBytes,
      );
      final List<String> recoveryCodes = await service.confirm(
        userId: auth.userId,
        code: body.requireString('code', maxLength: maxTwoFactorCodeLength),
      );
      return ApiResponse.ok(<String, Object?>{
        'enabled': true,
        'recovery_codes': recoveryCodes,
      });
    }),
  );

  router.post(
    '/v1/me/2fa/verify',
    rateLimitMiddleware(
      limiter: limiter,
      scope: 'two_factor',
      applies: (Request request) => true,
    )((Request request) async {
      final AuthContext auth = requireAuthContext(request);
      final JsonBody body = await JsonBody.fromRequest(
        request,
        maxBytes: config.maxBodyBytes,
      );
      final TwoFactorVerification verification = await service.verify(
        userId: auth.userId,
        code: body.requireString('code', maxLength: maxTwoFactorCodeLength),
      );
      return ApiResponse.ok(verification.toJson());
    }),
  );

  router.delete('/v1/me/2fa', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    await service.disable(auth.userId);
    return ApiResponse.ok(<String, Object?>{'enabled': false});
  });
}

/// La lecture de formule utilisée quand le service ne fournit pas la
/// formule du compte.
///
/// Sans formule, aucun compte n'est tenu d'activer la double
/// authentification : l'appelant qui veut l'obligation passe sa propre
/// lecture.
Future<String?> _freePlan(String userId) async => null;
