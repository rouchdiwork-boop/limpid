import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/features/billing/billing_formatters.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Les métadonnées commerciales publiées d'un livre.
///
/// La carte ne montre que ce que l'auteur a publié : une métadonnée absente
/// n'a pas de ligne, et un livre qui n'a rien publié n'a pas de carte.
class PublicationMetadataCard extends StatelessWidget {
  /// Crée la carte des métadonnées d'un livre.
  const PublicationMetadataCard({required this.metadata, super.key});

  /// Les métadonnées publiées du livre.
  final PublicationMetadata metadata;

  @override
  Widget build(BuildContext context) {
    if (metadata.isEmpty) return const SizedBox.shrink();
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final List<(String, String)> rows = <(String, String)>[
      if (metadata.isbn.isNotEmpty)
        (strings.projectMetadataIsbn, metadata.isbn),
      if (metadata.language.isNotEmpty)
        (strings.projectMetadataLanguage, metadata.language),
      if (metadata.priceInCents != null)
        (strings.projectMetadataPrice, _priceOf(context)),
      if (metadata.contributors.isNotEmpty)
        (strings.fieldAuthorName, metadata.contributors.join(', ')),
    ];

    return LimpidCard(
      title: strings.projectMetadataTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final (String, String) row in rows)
            Padding(
              padding: EdgeInsets.only(bottom: scope.spacing.space8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      row.$1,
                      style: textTheme.bodySmall?.copyWith(
                        color: scope.colors.fgMuted,
                      ),
                    ),
                  ),
                  Text(
                    row.$2,
                    style: textTheme.bodySmall?.copyWith(
                      color: scope.colors.fgDefault,
                      fontFamily: LimpidFontFamily.mono,
                    ),
                  ),
                ],
              ),
            ),
          if (metadata.description.isNotEmpty) ...<Widget>[
            SizedBox(height: scope.spacing.space8),
            Text(
              metadata.description,
              style: textTheme.bodyMedium?.copyWith(
                color: scope.colors.fgDefault,
                fontFamily: LimpidFontFamily.manuscript,
                height: 1.6,
              ),
            ),
          ],
          if (metadata.categories.isNotEmpty) ...<Widget>[
            SizedBox(height: scope.spacing.space12),
            _Tags(label: strings.kdpBisac, values: metadata.categories),
          ],
          if (metadata.keywords.isNotEmpty) ...<Widget>[
            SizedBox(height: scope.spacing.space12),
            _Tags(label: strings.kdpKeywords, values: metadata.keywords),
          ],
        ],
      ),
    );
  }

  /// The price written in the currency of the sale.
  ///
  /// A book sells in euros: the currency is written only when it is not the
  /// euro, so that the reader always knows what they pay.
  String _priceOf(BuildContext context) {
    final int? cents = metadata.priceInCents;
    if (cents == null) return '';
    if (cents == 0) return AppLocalizations.of(context).salePriceFree;
    if (metadata.currency.toLowerCase() == 'eur') return formatPrice(cents);
    return '${cents ~/ 100} ${metadata.currency}';
  }
}

/// A list of published values under their label.
class _Tags extends StatelessWidget {
  const _Tags({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space8),
        Wrap(
          spacing: scope.spacing.space8,
          runSpacing: scope.spacing.space8,
          children: <Widget>[
            for (final String value in values) LimpidTag(label: value),
          ],
        ),
      ],
    );
  }
}
