import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Demande le message d'un commentaire.
///
/// La fenêtre montre les mots commentés : l'auteur sait ce qu'il commente
/// avant d'écrire. Renvoie `null` quand l'auteur renonce.
Future<String?> showCommentComposer(
  BuildContext context, {
  required String excerpt,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => _CommentComposer(excerpt: excerpt),
  );
}

/// La fenêtre qui demande le message d'un commentaire.
///
/// Le champ porte son propre contrôleur : il est libéré quand la fenêtre
/// disparaît, pas avant. Le bouton reste désactivé tant que le message est
/// vide : un fil ne se crée jamais sans mot.
final class _CommentComposer extends StatefulWidget {
  /// Crée la fenêtre du commentaire.
  const _CommentComposer({required this.excerpt});

  /// Les mots commentés.
  final String excerpt;

  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

/// L'état de la fenêtre du commentaire.
final class _CommentComposerState extends State<_CommentComposer> {
  /// Le contrôleur du champ.
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope tokens = context.limpid;

    return LimpidDialog(
      title: strings.revisionCommentTitle,
      icon: LimpidIcons.comment,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.text,
          onPressed: () => _closeComposer(context),
        ),
        LimpidButton(
          label: strings.revisionComment,
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => _closeComposer(context, _controller.text.trim()),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: EdgeInsets.all(tokens.spacing.space12),
            decoration: BoxDecoration(
              color: tokens.colors.bgCanvas,
              borderRadius: BorderRadius.circular(tokens.radii.sm),
              border: Border.all(color: tokens.colors.borderSubtle),
            ),
            child: Text(
              widget.excerpt,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          SizedBox(height: tokens.spacing.space16),
          LimpidTextField(
            controller: _controller,
            hint: strings.revisionCommentHint,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            onChanged: (String _) => setState(() {}),
            onSubmitted: (String value) {
              final String trimmed = value.trim();
              if (trimmed.isEmpty) {
                return;
              }
              _closeComposer(context, trimmed);
            },
          ),
        ],
      ),
    );
  }
}

/// Ferme la fenêtre du commentaire, en rendant [value] quand elle en a un.
///
/// Le dialogue est posé sur le navigateur racine : les écrans vivent dans
/// une branche du shell, et une fermeture prise dans la branche ne fermerait
/// pas la fenêtre.
void _closeComposer(BuildContext context, [Object? value]) {
  Navigator.of(context, rootNavigator: true).pop(value);
}
