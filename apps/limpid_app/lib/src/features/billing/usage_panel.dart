import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/features/billing/billing_formatters.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'usage du cycle en cours.
///
/// Le panneau montre les trois jauges de la formule : les mots écrits, l'usage
/// de l'IA et le stockage. Une jauge que le serveur ne mesure pas reste
/// vide — l'écran ne remplit jamais une barre avec un chiffre inventé.
class UsagePanel extends StatelessWidget {
  /// Crée le panneau.
  const UsagePanel({
    super.key,
    required this.readings,
    required this.periodStart,
    required this.periodEnd,
  });

  /// Les lectures des trois grandeurs.
  final List<QuotaReading> readings;

  /// Le début du cycle, quand il est connu.
  final DateTime? periodStart;

  /// La fin du cycle, quand elle est connue.
  final DateTime? periodEnd;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String? cycle = _cycleLabel(context);

    return LimpidCard(
      padding: EdgeInsets.all(scope.spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  strings.billingUsageTitle,
                  style: textTheme.titleMedium?.copyWith(
                    color: scope.colors.fgDefault,
                  ),
                ),
              ),
              if (cycle != null) LimpidChip(label: cycle),
            ],
          ),
          SizedBox(height: scope.spacing.space16),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final List<Widget> gauges = <Widget>[
                for (final QuotaReading reading in readings)
                  _Gauge(reading: reading),
              ];
              if (constraints.maxWidth >= _gaugeBreakpoint) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (
                      var index = 0;
                      index < gauges.length;
                      index++
                    ) ...<Widget>[
                      if (index > 0) SizedBox(width: scope.spacing.space16),
                      Expanded(child: gauges[index]),
                    ],
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (
                    var index = 0;
                    index < gauges.length;
                    index++
                  ) ...<Widget>[
                    if (index > 0) SizedBox(height: scope.spacing.space12),
                    gauges[index],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// La période du cycle, écrite dans la langue de l'interface.
  ///
  /// La période est lue du serveur : l'écran ne la devine pas.
  String? _cycleLabel(BuildContext context) {
    final DateTime? start = periodStart;
    final DateTime? end = periodEnd;
    if (start == null || end == null) return null;
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    return '${localizations.formatMediumDate(start)} – '
        '${localizations.formatMediumDate(end)}';
  }

  /// La largeur à partir de laquelle les trois jauges tiennent sur une ligne.
  static const double _gaugeBreakpoint = 560;
}

/// Une jauge : le nom d'une grandeur, sa barre et sa consommation.
class _Gauge extends StatelessWidget {
  /// Crée une jauge.
  const _Gauge({required this.reading});

  /// La lecture de la grandeur.
  final QuotaReading reading;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _labelOf(strings, reading.meter),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space6),
        LimpidLinearProgress(value: reading.ratio),
        SizedBox(height: scope.spacing.space6),
        Text(
          _figureOf(strings, reading),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scope.colors.fgSubtle),
        ),
      ],
    );
  }

  /// Le nom de la grandeur.
  String _labelOf(AppLocalizations strings, QuotaMeter meter) =>
      switch (meter) {
        QuotaMeter.words => strings.billingWords,
        QuotaMeter.aiUsage => strings.billingAiRewrites,
        QuotaMeter.storage => strings.billingStorage,
      };

  /// La consommation de la grandeur.
  ///
  /// La limite seule est affichée quand la consommation n'est pas mesurée :
  /// la jauge dit ce que la formule autorise, jamais ce qu'elle a coûté.
  String _figureOf(AppLocalizations strings, QuotaReading reading) {
    final int? limit = reading.limit;
    final int? used = reading.used;
    if (limit == null) return '—';
    if (used == null) return _format(reading.meter, limit);
    return strings.billingUsageOf(
      _format(reading.meter, limit),
      _format(reading.meter, used),
    );
  }

  /// Écrit une valeur dans l'unité de sa grandeur.
  String _format(QuotaMeter meter, int value) {
    if (meter == QuotaMeter.storage) return formatBytes(value);
    return formatCount(value);
  }
}
