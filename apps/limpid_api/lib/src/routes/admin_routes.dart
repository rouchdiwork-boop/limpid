import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../db/admin_database.dart';
import '../db/feature_flag.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../http/pagination.dart';
import '../services/admin_service.dart';

/// Registers the routes of the back-office.
///
/// The routes list the accounts the API knows and drive the indicators of
/// functionality. Every route refuses the caller that is not an
/// administrator: the check reads the claim of the verified token, never a
/// role sent by the client.
void registerAdminRoutes(
  Router router,
  AdminDatabase database,
  AppConfig config,
) {
  final AdminService service = AdminService(database);

  router.get('/v1/admin/users', (Request request) async {
    final PageRequest page = PageRequest.fromQuery(
      request.url.queryParameters,
      defaultLimit: config.defaultPageLimit,
      maxLimit: config.maxPageLimit,
    );
    final AccountPage accounts = await service.listAccounts(
      request: request,
      page: page,
    );
    return ApiResponse.paginated(
      items: accounts.items.map(_accountJson).toList(growable: false),
      total: accounts.total,
      page: page.page,
      limit: page.limit,
      nextCursor: accounts.nextCursor,
    );
  });

  router.get('/v1/admin/users/<userId>', (
    Request request,
    String userId,
  ) async {
    final AdminAccount account = await service.findAccount(
      request: request,
      userId: userId,
    );
    return ApiResponse.ok(_accountJson(account));
  });

  router.get('/v1/admin/feature-flags', (Request request) async {
    final List<FeatureFlag> flags = await service.listFeatureFlags(
      request: request,
    );
    return ApiResponse.ok(flags.map(_flagJson).toList(growable: false));
  });

  router.put('/v1/admin/feature-flags/<key>', (
    Request request,
    String key,
  ) async {
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final bool isEnabled = body.requireBool('enabled');
    final String? description = body.optionalString(
      'description',
      maxLength: AdminService.maxFeatureFlagDescriptionLength,
    );
    final FeatureFlag flag = await service.setFeatureFlag(
      request: request,
      key: key,
      isEnabled: isEnabled,
      description: description,
    );
    return ApiResponse.ok(_flagJson(flag));
  });
}

/// The JSON of an account.
Map<String, Object?> _accountJson(AdminAccount account) {
  return <String, Object?>{
    'user_id': account.userId,
    'plan': account.plan,
    'project_count': account.projectCount,
    'collaboration_count': account.collaborationCount,
    'comment_count': account.commentCount,
    'operation_count': account.operationCount,
    'last_activity_at': _isoOf(account.lastActivityAt),
    'is_purged': account.isPurged,
  };
}

/// The JSON of an indicator of functionality.
Map<String, Object?> _flagJson(FeatureFlag flag) {
  return <String, Object?>{
    'key': flag.key,
    'is_enabled': flag.isEnabled,
    'description': flag.description,
    'updated_at': flag.updatedAt.toUtc().toIso8601String(),
    'updated_by': flag.updatedBy,
  };
}

/// The ISO 8601 form of a date, `null` when it is absent.
String? _isoOf(DateTime? value) => value?.toUtc().toIso8601String();
