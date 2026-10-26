import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../db/admin_database.dart';
import '../db/feature_flag.dart';
import '../db/quota_database.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../http/pagination.dart';
import '../services/admin_service.dart';
import '../services/quota_service.dart';

/// Registers the routes of the back-office.
///
/// The routes list the accounts the API knows and drive the indicators of
/// functionality. Every route refuses the caller that is not an
/// administrator: the check reads the claim of the verified token, never a
/// role sent by the client.
///
/// [quota] carries the plans. It is optional: a server that does not wire it
/// does not serve the route that grants a paid plan.
void registerAdminRoutes(
  Router router,
  AdminDatabase database,
  AppConfig config, {
  QuotaService? quota,
}) {
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

  // Attribue une formule payée à un compte, après un paiement.
  //
  // La route est réservée à l'administrateur : le compte lui-même ne peut
  // pas s'attribuer une formule qu'il n'a pas payée.
  router.put('/v1/admin/plans/<userId>', (
    Request request,
    String userId,
  ) async {
    AdminService.requireAdmin(request);
    final QuotaService? service = quota;
    if (service == null) {
      throw const ServiceUnavailableException(
        message: 'Le service des formules n\'est pas configuré sur ce poste.',
      );
    }
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String planKey = body.requireString('plan');
    final SubscriptionPlan? plan = _readPlan(planKey);
    if (plan == null) {
      throw ValidationException(
        field: 'plan',
        message:
            'Le champ « plan » doit valoir '
            '${SubscriptionPlan.values.map((SubscriptionPlan value) => value.name).join(', ')}.',
      );
    }
    final BillingPeriod period = _readPeriod(
      body.optionalString('period') ?? BillingPeriod.monthly.name,
    );
    final AccountPlan assignment = await service.changePlan(
      userId: userId,
      plan: plan,
      period: period,
      paymentReference: body.optionalString('payment_reference'),
    );
    return ApiResponse.ok(assignment.toJson());
  });
}

/// The plan named [raw], `null` when it is unknown.
SubscriptionPlan? _readPlan(String raw) {
  final String normalized = raw.trim().toLowerCase();
  for (final SubscriptionPlan plan in SubscriptionPlan.values) {
    if (plan.name == normalized) return plan;
  }
  return null;
}

/// The billing period named [raw], the monthly one when it is unknown.
BillingPeriod _readPeriod(String raw) {
  final String normalized = raw.trim().toLowerCase();
  for (final BillingPeriod period in BillingPeriod.values) {
    if (period.name == normalized) return period;
  }
  return BillingPeriod.monthly;
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
