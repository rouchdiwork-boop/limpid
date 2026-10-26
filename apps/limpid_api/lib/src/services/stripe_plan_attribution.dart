import 'package:limpid_core/limpid_core.dart';

import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../db/quota_database.dart';
import '../logging/logger.dart';
import 'plan_catalog.dart';
import 'quota_service.dart';
import 'stripe_event.dart';

/// Le suffixe du nom d'une formule payée sur le cycle annuel.
const String _yearlySuffix = '_yearly';

/// L'attribution des formules aux comptes, à partir des événements Stripe.
///
/// L'attribution porte les règles du domaine : un paiement confirmé donne
/// la formule payée, un changement de formule applique la nouvelle, une
/// résiliation ramène le compte à la formule gratuite. Chaque effet est
/// tracé dans le journal d'audit (D-19).
///
/// L'attribution ne connaît pas la signature ni l'idempotence : elle reçoit
/// un événement déjà vérifié et déjà réservé.
final class StripePlanAttribution {
  /// Crée l'attribution.
  StripePlanAttribution({
    required this.quota,
    required this.audit,
    this.logger,
  });

  /// Le service qui porte les formules et les quotas.
  final QuotaService quota;

  /// Le journal d'audit.
  final AuditLog audit;

  /// Le journal du serveur, `null` quand l'attribution est sans journal.
  ///
  /// Il ne reçoit que des identifiants : ni le corps de la livraison, ni
  /// les données de paiement.
  final Logger? logger;

  /// Attribue la formule payée, quand le paiement est confirmé.
  ///
  /// Une session dont le paiement n'est pas encaissé n'attribue aucune
  /// formule : c'est le paiement qui l'attribue, pas la session.
  ///
  /// Rend l'action tracée dans le journal d'audit, `null` quand l'événement
  /// ne permet pas d'attribuer de formule.
  Future<String?> applyPayment(StripeEvent event, {String? ip}) async {
    if (event.paymentStatus != 'paid') {
      logger?.info('stripe.webhook.payment_not_confirmed', <String, Object?>{
        'event_id': event.id,
        'event_type': event.type,
        'payment_status': event.paymentStatus,
      });
      return null;
    }
    final String? userId = event.userId;
    if (userId == null) {
      logger?.warning('stripe.webhook.account_unknown', <String, Object?>{
        'event_id': event.id,
        'event_type': event.type,
      });
      return null;
    }
    final _PaidPlan? paid = _readPaidPlan(event.planKey);
    if (paid == null) {
      logger?.warning('stripe.webhook.plan_unknown', <String, Object?>{
        'event_id': event.id,
        'event_type': event.type,
      });
      return null;
    }
    final String? reference = event.reference;
    if (reference == null) {
      logger?.warning(
        'stripe.webhook.payment_reference_unknown',
        <String, Object?>{'event_id': event.id, 'event_type': event.type},
      );
      return null;
    }

    final AccountPlan previous = await quota.planOf(userId);
    await quota.changePlan(
      userId: userId,
      plan: paid.plan,
      period: paid.period,
      paymentReference: reference,
    );
    await audit.record(
      AuditEntry(
        userId: userId,
        action: 'plan.payment_confirmed',
        targetType: 'subscription',
        targetId: reference,
        metadata: <String, Object?>{
          'plan': paid.plan.name,
          'previous_plan': previous.plan.name,
          'period': paid.period.name,
          'payment_reference': reference,
          'event_id': event.id,
          'event_type': event.type,
        },
        ip: ip,
      ),
    );
    return 'plan.payment_confirmed';
  }

  /// Applique le changement de formule annoncé par Stripe.
  ///
  /// L'essai du compte n'est pas rendu : un changement de formule laisse
  /// l'essai consommé, et ne redonne pas d'essai.
  Future<String?> applySubscriptionUpdate(
    StripeEvent event, {
    String? ip,
  }) async {
    // Un abonnement résilié reste une annulation, même quand Stripe
    // l'annonce par une mise à jour.
    if (event.subscriptionStatus == 'canceled') {
      return applyCancellation(event, ip: ip);
    }
    final String? userId = event.userId;
    if (userId == null) {
      logger?.warning('stripe.webhook.account_unknown', <String, Object?>{
        'event_id': event.id,
        'event_type': event.type,
      });
      return null;
    }
    final _PaidPlan? paid = _readPaidPlan(event.planKey);
    final String? reference = event.reference;
    if (paid == null || reference == null) {
      logger?.warning(
        'stripe.webhook.subscription_unresolved',
        <String, Object?>{'event_id': event.id, 'event_type': event.type},
      );
      return null;
    }

    final AccountPlan previous = await quota.planOf(userId);
    await quota.changePlan(
      userId: userId,
      plan: paid.plan,
      period: paid.period,
      paymentReference: reference,
    );
    await audit.record(
      AuditEntry(
        userId: userId,
        action: 'plan.subscription_changed',
        targetType: 'subscription',
        targetId: reference,
        metadata: <String, Object?>{
          'plan': paid.plan.name,
          'previous_plan': previous.plan.name,
          'period': paid.period.name,
          'payment_reference': reference,
          'event_id': event.id,
          'event_type': event.type,
        },
        ip: ip,
      ),
    );
    return 'plan.subscription_changed';
  }

  /// Retire la formule payée du compte, quand l'abonnement est résilié.
  ///
  /// Le compte retombe sur la formule gratuite, et son essai reste
  /// consommé : une résiliation ne redonne pas d'essai.
  Future<String?> applyCancellation(StripeEvent event, {String? ip}) async {
    final String? userId = event.userId;
    if (userId == null) {
      logger?.warning('stripe.webhook.account_unknown', <String, Object?>{
        'event_id': event.id,
        'event_type': event.type,
      });
      return null;
    }
    final AccountPlan previous = await quota.planOf(userId);
    if (previous.plan == SubscriptionPlan.free) {
      // Le compte est déjà gratuit : il n'y a rien à retirer, et rien à
      // tracer.
      return null;
    }
    await quota.changePlan(
      userId: userId,
      plan: SubscriptionPlan.free,
      period: BillingPeriod.monthly,
    );
    await audit.record(
      AuditEntry(
        userId: userId,
        action: 'plan.subscription_cancelled',
        targetType: 'subscription',
        targetId: event.reference ?? event.id,
        metadata: <String, Object?>{
          'plan': SubscriptionPlan.free.name,
          'previous_plan': previous.plan.name,
          'event_id': event.id,
          'event_type': event.type,
        },
        ip: ip,
      ),
    );
    return 'plan.subscription_cancelled';
  }

  /// La formule payée nommée par [key], `null` quand elle est inconnue.
  ///
  /// Le nom porte le cycle : `studio_yearly` désigne la formule Studio sur
  /// le cycle annuel. La formule gratuite n'est jamais attribuée par un
  /// paiement : elle ne demande pas de paiement.
  static _PaidPlan? _readPaidPlan(String? key) {
    if (key == null) return null;
    final String normalized = key.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    String name = normalized;
    BillingPeriod period = BillingPeriod.monthly;
    if (name.endsWith(_yearlySuffix)) {
      name = name.substring(0, name.length - _yearlySuffix.length);
      period = BillingPeriod.yearly;
    }
    SubscriptionPlan? plan;
    for (final SubscriptionPlan candidate in SubscriptionPlan.values) {
      if (candidate.name == name) {
        plan = candidate;
        break;
      }
    }
    if (plan == null || plan == SubscriptionPlan.free) return null;
    if (period == BillingPeriod.yearly &&
        !PlanCatalog.offersYearlyCycle(plan)) {
      return null;
    }
    return _PaidPlan(plan: plan, period: period);
  }
}

/// Une formule payée et son cycle de facturation.
final class _PaidPlan {
  const _PaidPlan({required this.plan, required this.period});

  /// La formule payée.
  final SubscriptionPlan plan;

  /// Le cycle de facturation.
  final BillingPeriod period;
}
