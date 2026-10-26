import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La taille des icônes de la bande, en pixels logiques.
const double _kIconSize = 16;

/// La bande qui propose de commenter le passage sélectionné.
///
/// La bande ne parle que de la sélection : elle montre les mots que l'auteur
/// a choisis et l'action qui les commente. Elle disparaît dès que la
/// sélection s'efface.
class WritingSelectionBar extends StatelessWidget {
  /// Crée la bande de la sélection.
  const WritingSelectionBar({
    required this.excerpt,
    required this.onComment,
    super.key,
  });

  /// Les mots que l'auteur a sélectionnés.
  final String excerpt;

  /// Appelé quand l'auteur demande de commenter le passage.
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope tokens = context.limpid;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: tokens.spacing.space24),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.space12,
        vertical: tokens.spacing.space8,
      ),
      decoration: BoxDecoration(
        color: tokens.colors.bgSurface,
        borderRadius: BorderRadius.circular(tokens.radii.sm),
        border: Border.all(color: tokens.colors.secondary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(
            LimpidIcons.comment,
            size: _kIconSize,
            color: tokens.colors.secondary,
          ),
          SizedBox(width: tokens.spacing.space8),
          Text(
            strings.editorSelection,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: tokens.colors.fgMuted),
          ),
          SizedBox(width: tokens.spacing.space8),
          Expanded(
            child: Text(
              excerpt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          SizedBox(width: tokens.spacing.space12),
          LimpidButton(
            label: strings.revisionComment,
            icon: LimpidIcons.comment,
            variant: LimpidButtonVariant.secondary,
            size: LimpidButtonSize.small,
            onPressed: onComment,
          ),
        ],
      ),
    );
  }
}
