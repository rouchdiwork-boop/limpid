import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../db/quota_database.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/feature_flag_service.dart';
import '../services/plan_catalog.dart';
import '../services/quota_gauges.dart';
import '../services/quota_service.dart';
import '../services/webhook_dispatcher.dart';

/// Enregistre les routes des formules et des quotas.
///
/// Les trois routes de lecture décrivent la formule du compte, ses
/// compteurs et le catalogue public. La quatrième change la formule du
/// compte et trace l'action dans le journal d'audit (D-19).
///
/// Le journal d'audit est un paramètre nommé facultatif : le changement de
/// formule **exige** la trace, et la route refuse la demande quand le
/// journal n'est pas câblé. Le point de composition passe
/// `audit: dependencies.audit`.
///
/// Le dispatcher est, lui, facultatif et silencieux : sans lui, le changement
/// de formule n'est pas annoncé, mais il reste appliqué.
///
/// Les jauges sont mesurées par le port `gauges` : sans lui, la route
/// publie des jauges à zéro. Le point de composition passe
/// `gauges: AccountQuotaGauges(...)`.
void registerQuotaRoutes(
  Router router,
  QuotaDatabase database,
  AppConfig config, {
  AuditLog? audit,
  WebhookDispatcher? dispatcher,
  QuotaGaugeReader? gauges,
  FeatureFlagService? flags,
}) {
  final QuotaService quota = QuotaService(
    database: database,
    dispatcher: dispatcher,
    gauges: gauges,
    flags: flags,
  );

  router.get('/v1/me/plan', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final AccountPlan plan = await quota.planOf(auth.userId);
    final PlanDefinition definition = PlanCatalog.definitionOf(plan.plan);
    final PlanStatus status = await quota.statusOf(auth.userId);

    return ApiResponse.ok(<String, Object?>{
      'plan': plan.plan.name,
      'name': definition.displayName,
      'status': status.key,
      'period': plan.period.name,
      'trial_ends_at': plan.trialEndsAt?.toUtc().toIso8601String(),
      'period_started_at': plan.periodStartedAt.toUtc().toIso8601String(),
      'period_ends_at': plan.periodEndsAt?.toUtc().toIso8601String(),
      'seat_count': definition.quota.maxSeats,
      // Les capacites annoncees sont celles que le compte peut
      // effectivement utiliser : une capacite coupee par un indicateur du
      // back-office disparait de la liste.
      'capabilities':
          await flags?.announcedCapabilities(plan.plan) ??
          <String>[
            for (final PlanCapability capability in PlanCapability.values)
              if (PlanCatalog.hasCapability(plan.plan, capability))
                capability.key,
          ],
    });
  });

  router.get('/v1/me/quota', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final QuotaSnapshot snapshot = await quota.snapshotOf(auth.userId);
    return ApiResponse.ok(snapshot.toJson());
  });

  router.get('/v1/plans', (Request request) async {
    return ApiResponse.ok(<Object?>[
      for (final SubscriptionPlan plan in PlanCatalog.all)
        PlanCatalog.toJson(plan),
    ]);
  });

  router.post('/v1/me/plan', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final AuditLog journal = _requireAudit(audit);
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

    final String periodKey =
        body.optionalString('period') ?? BillingPeriod.monthly.name;
    final BillingPeriod? period = _readPeriod(periodKey);
    if (period == null) {
      throw ValidationException(
        field: 'period',
        message:
            'Le champ « period » doit valoir '
            '${BillingPeriod.values.map((BillingPeriod value) => value.name).join(', ')}.',
      );
    }

    final AccountPlan previous = await quota.planOf(auth.userId);
    final AccountPlan assignment = await quota.changePlan(
      userId: auth.userId,
      plan: plan,
      period: period,
      startTrial: body.optionalBool('start_trial') ?? false,
    );

    await journal.record(
      AuditEntry(
        userId: auth.userId,
        action: 'plan.changed',
        targetType: 'subscription',
        targetId: auth.userId,
        metadata: <String, Object?>{
          'plan': assignment.plan.name,
          'previous_plan': previous.plan.name,
          'period': assignment.period.name,
          'trial_ends_at': assignment.trialEndsAt?.toUtc().toIso8601String(),
        },
        ip: clientIpOf(request),
      ),
    );

    return ApiResponse.ok(<String, Object?>{
      ...assignment.toJson(),
      'name': PlanCatalog.definitionOf(assignment.plan).displayName,
    });
  });
}

/// La formule de nom [key], `null` quand le nom est inconnu.
SubscriptionPlan? _readPlan(String key) {
  for (final SubscriptionPlan plan in SubscriptionPlan.values) {
    if (plan.name == key) return plan;
  }
  return null;
}

/// Le cycle de nom [key], `null` quand le nom est inconnu.
BillingPeriod? _readPeriod(String key) {
  for (final BillingPeriod period in BillingPeriod.values) {
    if (period.name == key) return period;
  }
  return null;
}

/// Le journal d'audit, ou une erreur qui refuse le changement de formule.
///
/// Un changement de formule n'est jamais discret : il est tracé dans le
/// journal d'audit (D-19). Sans journal, la route refuse la demande plutôt
/// que de l'appliquer sans trace.
AuditLog _requireAudit(AuditLog? audit) {
  if (audit != null) return audit;
  throw const ServiceUnavailableException(
    message:
        "Le journal d'audit n'est pas disponible : le changement de formule "
        'est refusé.',
  );
}
