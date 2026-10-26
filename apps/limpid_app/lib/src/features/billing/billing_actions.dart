/// Les actions de l'écran de formule.
///
/// Elles vivent à part de la page : la page dessine, les actions décident.
/// Une action qui échoue le dit à l'auteur — elle ne fait jamais semblant
/// qu'un paiement a commencé.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/billing/billing_providers.dart';
import 'package:limpid_app/src/features/billing/billing_side_panel.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'action « Choisir cette formule ».
///
/// La formule gratuite se change sans paiement ; les autres ouvrent une
/// session de paiement. Quand le service de paiement n'est pas configuré,
/// l'écran le dit au lieu de faire semblant.
Future<void> choosePlan(
  BuildContext context,
  WidgetRef ref,
  SubscriptionPlan plan,
  BillingPeriod period,
) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  try {
    if (plan == SubscriptionPlan.free) {
      await ref
          .read(checkoutProvider.notifier)
          .change(plan: plan, period: period);
      if (!context.mounted) return;
      LimpidSnackbar.show(
        context,
        message: strings.billingCurrentPlan,
        variant: LimpidStatusVariant.success,
      );
      return;
    }
    final CheckoutSession session = await ref
        .read(checkoutProvider.notifier)
        .open(plan: plan, period: period);
    if (!context.mounted) return;
    LimpidSnackbar.show(
      context,
      message: session.url,
      variant: LimpidStatusVariant.info,
    );
  } on ServiceUnavailableException {
    if (!context.mounted) return;
    LimpidSnackbar.show(
      context,
      message: strings.billingUnavailable,
      variant: LimpidStatusVariant.warning,
    );
  } on ApiValidationException catch (error) {
    if (!context.mounted) return;
    // Le serveur a refusé l'action : soit la formule ne permet pas ce
    // que l'auteur demande, soit le quota est atteint.
    final bool isQuota =
        error.code == 'plan_limit_reached' || error.code == 'quota_exceeded';
    LimpidSnackbar.show(
      context,
      message: isQuota
          ? strings.billingQuotaReached(PlanDefinition.of(plan).displayName)
          : strings.errorGeneric,
      variant: isQuota
          ? LimpidStatusVariant.warning
          : LimpidStatusVariant.danger,
    );
  } on Object {
    if (!context.mounted) return;
    LimpidSnackbar.show(
      context,
      message: strings.errorGeneric,
      variant: LimpidStatusVariant.danger,
    );
  }
}

/// L'action « Gérer » de la formule du compte.
///
/// Elle ouvre le panneau de facturation : sur un écran large, il est déjà
/// visible à droite ; sur un écran étroit, le dialogue l'amène à l'auteur.
Future<void> manageSubscription(BuildContext context, WidgetRef ref) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  final AccountPlan? account = ref.read(accountPlanProvider).value;
  final List<QuotaReading>? readings = ref.read(quotaUsageProvider).value;
  final CheckoutState checkout = ref.read(checkoutProvider);
  final bool isPaymentAvailable =
      ref.read(planRepositoryProvider) is! UnavailableService;

  await LimpidDialog.show<void>(
    context: context,
    title: strings.settingsPlan,
    icon: LimpidIcons.money,
    builder: (BuildContext context) => BillingSidePanel(
      plan: account,
      priceInCents: nextPaymentOf(account),
      consumption: consumptionOf(readings),
      session: checkout.session,
      isPaymentAvailable: isPaymentAvailable,
      onChangePaymentMethod: () => changePaymentMethod(context, ref),
      onInvoiceHistory: () => showInvoiceHistory(context),
    ),
  );
}

/// L'action « Modifier » du moyen de paiement.
Future<void> changePaymentMethod(BuildContext context, WidgetRef ref) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  final AccountPlan? account = ref.read(accountPlanProvider).value;
  if (account == null) {
    LimpidSnackbar.show(
      context,
      message: strings.errorGeneric,
      variant: LimpidStatusVariant.danger,
    );
    return;
  }
  await choosePlan(context, ref, account.plan, account.period);
}

/// L'action « Historique des factures ».
///
/// Le serveur n'expose pas encore les factures : l'écran le dit plutôt que
/// d'afficher un historique qu'il n'a pas lu.
void showInvoiceHistory(BuildContext context) {
  final AppLocalizations strings = AppLocalizations.of(context);
  LimpidSnackbar.show(
    context,
    message: strings.billingUnavailable,
    variant: LimpidStatusVariant.warning,
  );
}

/// Le montant du prochain prélèvement.
///
/// La formule gratuite ne se prélève pas : le panneau ne montre alors
/// aucun montant. Le cycle annuel n'existe que pour Studio : le montant
/// lu est celui du cycle réel du compte.
int? nextPaymentOf(AccountPlan? account) {
  if (account == null) return null;
  if (account.plan == SubscriptionPlan.free) return null;
  if (account.period == BillingPeriod.yearly) {
    return PlanDefinition.studioYearly.priceInCents;
  }
  return PlanDefinition.of(account.plan).priceInCents;
}

/// La consommation lue pour le cycle en cours.
///
/// Le panneau de facturation montre les mots écrits du cycle : c'est la
/// seule grandeur que le serveur et l'auteur ont en commun.
QuotaReading? consumptionOf(List<QuotaReading>? readings) {
  if (readings == null) return null;
  for (final QuotaReading reading in readings) {
    if (reading.meter == QuotaMeter.words) return reading;
  }
  return null;
}
