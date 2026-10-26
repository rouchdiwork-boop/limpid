import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/account_deletion.dart';
import '../services/personal_data_export.dart';

/// The action journaled when an author asks for the export of their data.
const String accountExportRequestedAction = 'account.export_requested';

/// Registers the routes of the account.
///
/// The two routes answer the obligations of the RGPD (D-19): the export of
/// the personal data and the deletion of the account. Both are protected:
/// the caller is the authenticated author, and the export never carries the
/// session of anybody else.
void registerAccountRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config,
) {
  router.get('/v1/me/export', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final PersonalDataExportService service = PersonalDataExportService(
      projects: dependencies.projects,
      sync: dependencies.sync,
      audit: dependencies.audit,
    );

    final Map<String, Object?> payload = await service.build(
      userId: auth.userId,
      email: auth.email,
    );

    await dependencies.audit.record(
      AuditEntry(
        userId: auth.userId,
        action: accountExportRequestedAction,
        targetType: 'account',
        targetId: auth.userId,
        metadata: _countsOf(payload),
        ip: clientIpOf(request),
      ),
    );

    return ApiResponse.ok(payload);
  });

  router.delete('/v1/me', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    if (!body.requireBool('confirm')) {
      throw const ValidationException(
        field: 'confirm',
        message:
            'La suppression du compte doit être confirmée explicitement : '
            'renvoyez « confirm » à true.',
      );
    }

    final AccountDeletionService service = AccountDeletionService(
      audit: dependencies.audit,
    );
    final AccountDeletion deletion = await service.request(
      userId: auth.userId,
      email: auth.email,
      ip: clientIpOf(request),
    );

    return ApiResponse.ok(deletion.toJson());
  });
}

/// The counters of the export, for the audit journal.
Map<String, Object?> _countsOf(Map<String, Object?> payload) {
  final Object? counts = payload['counts'];
  if (counts is Map<String, Object?>) return counts;
  return const <String, Object?>{};
}
