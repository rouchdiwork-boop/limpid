import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/features/billing/billing_formatters.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Le panneau de facturation.
///
/// Il tient ce que le serveur sait de l'abonnement : le prochain
/// prélèvement, la fin de l'essai, la session de paiement ouverte. Ce qu'il
/// ne sait pas — l'historique des factures, le moyen de paiement enregistré —
/// il le dit au lieu de l'inventer.
class BillingSidePanel extends StatelessWidget {
  /// Crée le panneau.
  const BillingSidePanel({
    super.key,
    required this.plan,
    required this.priceInCents,
    required this.consumption,
    required this.session,
    required this.isPaymentAvailable,
    required this.onChangePaymentMethod,
    required this.onInvoiceHistory,
  });

  /// L'abonnement du compte, `null` quand le serveur ne l'a pas lu.
  final AccountPlan? plan;

  /// Le montant du prochain prélèvement, `null` quand la formule est
  /// gratuite ou inconnue.
  final int? priceInCents;

  /// La consommation des mots écrits sur le cycle, quand elle est mesurée.
  final QuotaReading? consumption;

  /// La session de paiement ouverte, `null` quand aucune ne l'a été.
  final CheckoutSession? session;

  /// Indique si le service de paiement est configuré sur ce poste.
  final bool isPaymentAvailable;

  /// Appelée quand l'auteur veut changer de moyen de paiement.
  final VoidCallback onChangePaymentMethod;

  /// Appelée quand l'auteur veut l'historique des factures.
  final VoidCallback onInvoiceHistory;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final DateTime? trialEndsAt = plan?.trialEndsAt;

    return LimpidCard(
      padding: EdgeInsets.all(scope.spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(LimpidIcons.money, size: 18, color: scope.colors.accent),
              SizedBox(width: scope.spacing.space8),
              Text(
                strings.settingsPlan,
                style: textTheme.titleMedium?.copyWith(
                  color: scope.colors.fgDefault,
                ),
              ),
            ],
          ),
          SizedBox(height: scope.spacing.space16),
          _nextPayment(context, strings),
          SizedBox(height: scope.spacing.space16),
          _consumptionOf(context, strings),
          SizedBox(height: scope.spacing.space16),
          _paymentMethod(context, strings),
          if (trialEndsAt != null) ...<Widget>[
            SizedBox(height: scope.spacing.space16),
            LimpidBanner(
              variant: LimpidStatusVariant.info,
              title: strings.billingTrialBanner(_dateOf(context, trialEndsAt)),
            ),
          ],
          SizedBox(height: scope.spacing.space16),
          LimpidButton(
            label: strings.billingInvoiceHistory,
            variant: LimpidButtonVariant.secondary,
            expand: true,
            onPressed: onInvoiceHistory,
          ),
        ],
      ),
    );
  }

  /// Le prochain prélèvement : le montant et la date de fin de période.
  Widget _nextPayment(BuildContext context, AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final int? price = priceInCents;
    final DateTime? endsAt = plan?.periodEndsAt;
    if (price == null || endsAt == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.billingNextPayment,
          style: textTheme.labelMedium?.copyWith(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space8),
        Text(
          formatPrice(price),
          style: textTheme.headlineSmall?.copyWith(
            color: scope.colors.fgDefault,
          ),
        ),
        SizedBox(height: scope.spacing.space2),
        Text(
          _dateOf(context, endsAt),
          style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
        ),
      ],
    );
  }

  /// La consommation du cycle : les mots écrits depuis le début de la
  /// période.
  ///
  /// Le panneau ne montre la figure que lorsque le serveur l'a mesurée :
  /// une consommation inconnue reste absente.
  Widget _consumptionOf(BuildContext context, AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final QuotaReading? reading = consumption;
    if (reading == null || !reading.isMeasured) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.billingCurrentUsage,
          style: textTheme.labelMedium?.copyWith(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space8),
        Text(
          strings.billingUsageOf(
            formatCount(reading.limit!),
            formatCount(reading.used!),
          ),
          style: textTheme.bodyLarge?.copyWith(color: scope.colors.fgDefault),
        ),
      ],
    );
  }

  /// Le moyen de paiement : la session ouverte, quand elle l'est.
  Widget _paymentMethod(BuildContext context, AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final CheckoutSession? opened = session;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.billingPaymentMethod,
          style: textTheme.labelMedium?.copyWith(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space8),
        if (opened != null) ...<Widget>[
          SelectableText(
            opened.url,
            style: textTheme.bodySmall?.copyWith(color: scope.colors.accent),
          ),
          SizedBox(height: scope.spacing.space12),
        ],
        if (!isPaymentAvailable)
          Padding(
            padding: EdgeInsets.only(bottom: scope.spacing.space12),
            child: Text(
              strings.billingUnavailable,
              style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
            ),
          ),
        LimpidButton(
          label: strings.billingChangePaymentMethod,
          variant: LimpidButtonVariant.text,
          expand: true,
          onPressed: onChangePaymentMethod,
        ),
      ],
    );
  }

  /// Écrit une date dans la langue de l'interface.
  String _dateOf(BuildContext context, DateTime moment) {
    return MaterialLocalizations.of(context).formatMediumDate(moment);
  }
}
