import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/billing/billing_actions.dart';
import 'package:limpid_app/src/features/billing/billing_providers.dart';
import 'package:limpid_app/src/features/billing/billing_side_panel.dart';
import 'package:limpid_app/src/features/billing/plan_card.dart';
import 'package:limpid_app/src/features/billing/usage_panel.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'écran de formule et de facturation.
///
/// L'écran montre les quatre formules du catalogue avec leurs limites **en
/// chiffres**, le sélecteur de cycle, la consommation du cycle en cours et le
/// panneau de facturation. Sur un écran large, le panneau vit à droite de la
/// page ; sur un écran étroit, il passe sous les formules : l'écran se
/// réduit en une colonne.
class BillingScreen extends ConsumerWidget {
  /// Crée l'écran.
  const BillingScreen({super.key});

  /// La largeur à partir de laquelle le panneau de facturation passe à
  /// droite de la page.
  static const double _panelBreakpoint = 1000;

  /// La largeur du panneau de facturation.
  static const double _panelWidth = 340;

  /// Le nombre de colonnes de la grille des formules.
  static const int _wideColumns = 4;

  /// Le nombre de colonnes de la grille des formules sur un écran moyen.
  static const int _mediumColumns = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<AccountPlan> account = ref.watch(accountPlanProvider);
    final AsyncValue<List<PlanOffer>> offers = ref.watch(planOffersProvider);
    final AsyncValue<List<QuotaReading>> usage = ref.watch(quotaUsageProvider);
    final BillingPeriod period = ref.watch(billingPeriodProvider);
    final CheckoutState checkout = ref.watch(checkoutProvider);
    final bool isPaymentAvailable =
        ref.watch(planRepositoryProvider) is! UnavailableService;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isWide = constraints.maxWidth >= _panelBreakpoint;
            final List<Widget> blocks = <Widget>[
              _header(context, strings),
              SizedBox(height: scope.spacing.space24),
              _periodSelector(context, ref, strings, period),
              SizedBox(height: scope.spacing.space24),
              _planGrid(context, ref, strings, offers, account.value, period),
              SizedBox(height: scope.spacing.space24),
              _usage(account.value, usage.value),
            ];
            final Widget panel = _panel(
              context,
              ref,
              account.value,
              usage.value,
              checkout,
              isPaymentAvailable,
            );

            if (isWide) {
              return Row(
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.all(scope.spacing.space24),
                      children: blocks,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: _panelWidth,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(scope.spacing.space16),
                      child: panel,
                    ),
                  ),
                ],
              );
            }

            return ListView(
              padding: EdgeInsets.all(scope.spacing.space16),
              children: <Widget>[
                ...blocks,
                SizedBox(height: scope.spacing.space24),
                panel,
              ],
            );
          },
        ),
      ),
    );
  }

  /// Le titre et la phrase d'introduction de la page.
  Widget _header(BuildContext context, AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        Text(
          strings.billingTitle,
          textAlign: TextAlign.center,
          style: textTheme.headlineMedium?.copyWith(
            color: scope.colors.fgDefault,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: scope.spacing.space8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            strings.billingSubtitle,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
          ),
        ),
      ],
    );
  }

  /// Le sélecteur de cycle mensuel ou annuel.
  Widget _periodSelector(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations strings,
    BillingPeriod period,
  ) {
    final LimpidThemeScope scope = context.limpid;

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LimpidChip(
            label: strings.billingMonthly,
            isSelected: period == BillingPeriod.monthly,
            onTap: () => ref
                .read(billingPeriodProvider.notifier)
                .select(BillingPeriod.monthly),
          ),
          SizedBox(width: scope.spacing.space8),
          LimpidChip(
            label: '${strings.billingAnnual} ${strings.billingAnnualDiscount}',
            isSelected: period == BillingPeriod.yearly,
            onTap: () => ref
                .read(billingPeriodProvider.notifier)
                .select(BillingPeriod.yearly),
          ),
        ],
      ),
    );
  }

  /// La grille des formules.
  Widget _planGrid(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations strings,
    AsyncValue<List<PlanOffer>> offers,
    AccountPlan? account,
    BillingPeriod period,
  ) {
    return offers.when(
      data: (List<PlanOffer> list) =>
          _grid(context, ref, strings, list, account, period),
      loading: () => const Center(child: LimpidSpinner()),
      error: (Object error, StackTrace stack) =>
          _failure(context, ref, strings, error),
    );
  }

  /// La grille des formules, une fois le catalogue lu.
  Widget _grid(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations strings,
    List<PlanOffer> offers,
    AccountPlan? account,
    BillingPeriod period,
  ) {
    final LimpidThemeScope scope = context.limpid;
    if (offers.isEmpty) {
      return LimpidEmptyState(
        title: strings.dataEmptyTitle,
        message: strings.dataEmptyMessage,
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 1080
            ? _wideColumns
            : constraints.maxWidth >= 640
            ? _mediumColumns
            : 1;
        final List<Widget> rows = <Widget>[];
        for (int start = 0; start < offers.length; start += columns) {
          final List<PlanOffer> slice = offers.sublist(
            start,
            math.min(start + columns, offers.length),
          );
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int index = 0; index < slice.length; index++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: start + index == offers.length - 1
                              ? 0
                              : scope.spacing.space16,
                        ),
                        child: PlanCard(
                          offer: slice[index],
                          period: period,
                          isCurrent: account?.plan == slice[index].plan,
                          onChoose: () => choosePlan(
                            context,
                            ref,
                            slice[index].plan,
                            period,
                          ),
                          onManage: () => manageSubscription(context, ref),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
          if (start + columns < offers.length) {
            rows.add(SizedBox(height: scope.spacing.space16));
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  /// Le panneau de facturation.
  Widget _panel(
    BuildContext context,
    WidgetRef ref,
    AccountPlan? account,
    List<QuotaReading>? readings,
    CheckoutState checkout,
    bool isPaymentAvailable,
  ) {
    return BillingSidePanel(
      plan: account,
      priceInCents: nextPaymentOf(account),
      consumption: consumptionOf(readings),
      session: checkout.session,
      isPaymentAvailable: isPaymentAvailable,
      onChangePaymentMethod: () => changePaymentMethod(context, ref),
      onInvoiceHistory: () => showInvoiceHistory(context),
    );
  }

  /// Le panneau de l'usage du cycle.
  Widget _usage(AccountPlan? account, List<QuotaReading>? readings) {
    return UsagePanel(
      readings: readings ?? const <QuotaReading>[],
      periodStart: account?.periodStartedAt,
      periodEnd: account?.periodEndsAt,
    );
  }

  /// L'état d'échec de la lecture du catalogue.
  Widget _failure(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations strings,
    Object error,
  ) {
    if (error is ServiceUnavailableException) {
      return LimpidBanner(
        variant: LimpidStatusVariant.info,
        title: strings.billingUnavailable,
      );
    }
    return LimpidEmptyState(
      title: strings.errorGeneric,
      icon: LimpidIcons.error,
      action: LimpidButton(
        label: strings.actionRetry,
        onPressed: () => ref.invalidate(planOffersProvider),
      ),
    );
  }
}
