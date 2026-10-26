import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/features/billing/billing_formatters.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Une formule du catalogue.
///
/// La carte montre **ce que la formule contient en chiffres** : les mots,
/// l'usage de l'IA et le stockage. La formule du compte porte la pastille
/// « Formule actuelle » et le bouton « Gérer ».
class PlanCard extends StatelessWidget {
  /// Crée une carte de formule.
  const PlanCard({
    super.key,
    required this.offer,
    required this.period,
    required this.isCurrent,
    required this.onChoose,
    required this.onManage,
  });

  /// La formule décrite par la carte.
  final PlanOffer offer;

  /// Le cycle que l'auteur regarde.
  final BillingPeriod period;

  /// Indique si la carte décrit la formule du compte.
  final bool isCurrent;

  /// Appelée quand l'auteur choisit cette formule.
  final VoidCallback onChoose;

  /// Appelée quand l'auteur gère la formule du compte.
  final VoidCallback onManage;

  /// La hauteur de la rangée qui porte la pastille.
  ///
  /// Les quatre cartes gardent la même hauteur — et donc les boutons à la
  /// même ligne — qu'elles portent ou non la pastille de la formule du
  /// compte.
  static const double _badgeRowHeight = 30;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final BillingPeriod shown = offer.periodOf(period);

    return LimpidCard(
      elevation: isCurrent
          ? LimpidCardElevation.raised
          : LimpidCardElevation.outlined,
      accent: isCurrent ? scope.colors.accent : null,
      padding: EdgeInsets.all(scope.spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: _badgeRowHeight,
            child: isCurrent
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: LimpidBadge(
                      label: strings.billingCurrentPlan,
                      variant: LimpidStatusVariant.info,
                    ),
                  )
                : null,
          ),
          Text(
            LimpidTextTransform.label(offer.displayName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(
              color: scope.colors.fgMuted,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: scope.spacing.space6),
          Text(
            formatPrice(offer.priceFor(period)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.displaySmall?.copyWith(
              color: scope.colors.fgDefault,
            ),
          ),
          SizedBox(height: scope.spacing.space2),
          Text(
            _periodLabel(strings, shown),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
          ),
          SizedBox(height: scope.spacing.space16),
          ..._limits(context, strings),
          SizedBox(height: scope.spacing.space16),
          LimpidButton(
            label: isCurrent
                ? strings.billingManagePlan
                : strings.billingChoosePlan,
            variant: isCurrent
                ? LimpidButtonVariant.secondary
                : LimpidButtonVariant.primary,
            expand: true,
            onPressed: isCurrent ? onManage : onChoose,
          ),
        ],
      ),
    );
  }

  /// Les limites de la formule, une ligne par grandeur.
  ///
  /// Une grandeur sans limite n'a pas de ligne : la carte ne montre jamais
  /// un chiffre que la formule ne pose pas.
  List<Widget> _limits(BuildContext context, AppLocalizations strings) {
    final List<Widget> lines = <Widget>[];
    final int? words = offer.maxWords;
    if (words != null) {
      lines.add(
        _LimitLine(label: strings.billingWords, value: formatCount(words)),
      );
    }
    final int? ai = offer.maxAiUsage;
    if (ai != null) {
      lines.add(
        _LimitLine(label: strings.billingAiRewrites, value: formatCount(ai)),
      );
    }
    final int? storage = offer.maxStorageBytes;
    if (storage != null) {
      lines.add(
        _LimitLine(label: strings.billingStorage, value: formatBytes(storage)),
      );
    }
    return lines;
  }

  /// La mention du cycle suivi par le prix affiché.
  ///
  /// Le nombre de sièges accompagne le cycle : c'est la seule place où la
  /// formule Studio se distingue des trois autres.
  String _periodLabel(AppLocalizations strings, BillingPeriod shown) {
    final String cycle = shown == BillingPeriod.yearly
        ? strings.billingPerYear
        : strings.billingPerMonth;
    if (offer.seatCount <= 1) return cycle;
    return '$cycle$kSeparator${strings.billingSeats(offer.seatCount)}';
  }
}

/// Une limite de la formule, sur une ligne.
class _LimitLine extends StatelessWidget {
  /// Crée une ligne.
  const _LimitLine({required this.label, this.value});

  /// Le nom de la grandeur.
  final String label;

  /// La limite, `null` quand la ligne ne porte qu'un nom.
  final String? value;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: scope.spacing.space6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(LimpidIcons.check, size: 14, color: scope.colors.success),
          SizedBox(width: scope.spacing.space8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
            ),
          ),
          if (value != null) ...<Widget>[
            SizedBox(width: scope.spacing.space8),
            Flexible(
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: scope.colors.fgDefault,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
