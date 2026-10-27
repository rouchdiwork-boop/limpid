import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../middleware/rate_limiter.dart';
import '../services/ai_consent_service.dart';

/// Enregistre les routes du consentement à l'IA (D-08).
///
/// Trois routes décrivent la décision de l'auteur :
/// - la lecture dit si le compte a autorisé l'envoi de son texte à un tiers,
///   et quand il l'a fait ;
/// - l'écriture pose son accord ;
/// - la suppression le retire.
///
/// Le retrait est effectif : dès qu'il est enregistré, plus aucun appel ne
/// part chez la fournisseur. Les deux décisions sont tracées dans le journal
/// d'audit, sans aucun texte de l'auteur.
///
/// [consents] porte la décision : le service lit l'état et l'écrit. La route
/// ne fait que dire à l'auteur ce que son compte a décidé, et tracer la
/// décision.
void registerAiConsentRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  required AiConsentService consents,
}) {
  // La lecture de l'état du consentement.
  router.get('/v1/me/ai-consent', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final AiConsentState state = await consents.stateOf(userId: auth.userId);
    return ApiResponse.ok(state.toJson());
  });

  // L'accord de l'auteur.
  router.post('/v1/me/ai-consent', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    await _drainBody(request, config);
    final AiConsentState state = await consents.grant(userId: auth.userId);
    await _trace(
      request,
      dependencies.audit,
      userId: auth.userId,
      action: 'ai.consent_granted',
      state: state,
    );
    return ApiResponse.ok(state.toJson());
  });

  // Le retrait de l'accord.
  router.delete('/v1/me/ai-consent', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    await _drainBody(request, config);
    final AiConsentState state = await consents.revoke(userId: auth.userId);
    await _trace(
      request,
      dependencies.audit,
      userId: auth.userId,
      action: 'ai.consent_revoked',
      state: state,
    );
    return ApiResponse.ok(state.toJson());
  });
}

/// Écrit la trace d'une décision de l'auteur.
///
/// La trace porte le fournisseur et le périmètre : elle dit **qui** a
/// décidé et **de quoi**. Elle ne porte aucun texte de l'auteur, et le
/// compte n'y est qu'un identifiant.
Future<void> _trace(
  Request request,
  AuditLog journal, {
  required String userId,
  required String action,
  required AiConsentState state,
}) {
  return journal.record(
    AuditEntry(
      userId: userId,
      action: action,
      targetType: 'ai_consent',
      targetId: state.provider,
      metadata: <String, Object?>{
        'scope': state.scope,
        'provider': state.provider,
      },
      ip: clientIpOf(request),
    ),
  );
}

/// Lit le corps de la requête, quand il y en a un, et l'écarte.
///
/// Poser ou retirer un accord ne demande aucun corps : le client ne choisit
/// ni le périmètre, ni le fournisseur — ce sont ceux du serveur. Le corps
/// est donc lu pour ne pas laisser la requête à moitié lue, et un corps trop
/// gros est refusé comme sur les autres routes.
Future<void> _drainBody(Request request, AppConfig config) async {
  final int? length = request.contentLength;
  if (length != null && length > config.maxBodyBytes) {
    throw PayloadTooLargeException(
      limitBytes: config.maxBodyBytes,
      message: 'Le corps de la requête dépasse la taille maximale autorisée.',
    );
  }
  await request.readAsString();
}
