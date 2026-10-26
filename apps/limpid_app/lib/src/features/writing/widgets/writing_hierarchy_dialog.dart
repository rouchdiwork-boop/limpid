/// La boîte de dialogue qui demande le titre d'un élément de la hiérarchie.
///
/// Les dialogues vivent avec la fonctionnalité qui les possède : le plan du
/// livre les ouvre, il ne répète pas leur construction.
library;

import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Demande le titre du nouvel élément de la hiérarchie.
///
/// Le paramètre [title] nomme l'élément demandé — « Ajouter un tome », par
/// exemple. La fonction renvoie `null` quand l'auteur renonce.
Future<String?> showHierarchyTitleDialog({
  required BuildContext context,
  required String title,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => _HierarchyTitleDialog(title: title),
  );
}

/// La boîte de dialogue qui demande le titre d'un élément de la hiérarchie.
///
/// Le champ porte son propre contrôleur : il est libéré quand la boîte
/// disparaît, pas avant.
final class _HierarchyTitleDialog extends StatefulWidget {
  /// Crée la boîte de dialogue.
  const _HierarchyTitleDialog({required this.title});

  /// Le nom de l'élément demandé.
  final String title;

  @override
  State<_HierarchyTitleDialog> createState() => _HierarchyTitleDialogState();
}

/// L'état de la boîte de dialogue du titre.
final class _HierarchyTitleDialogState extends State<_HierarchyTitleDialog> {
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

    return LimpidDialog(
      title: widget.title,
      icon: LimpidIcons.add,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.text,
          onPressed: () => _closeDialog(context),
        ),
        LimpidButton(
          label: strings.actionCreate,
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => _closeDialog(context, _controller.text.trim()),
        ),
      ],
      child: LimpidTextField(
        controller: _controller,
        label: strings.hierarchyTitle,
        autofocus: true,
        onChanged: (String _) => setState(() {}),
        onSubmitted: (String value) {
          final String trimmed = value.trim();
          if (trimmed.isEmpty) return;
          _closeDialog(context, trimmed);
        },
      ),
    );
  }
}

/// Ferme la boîte de dialogue, en rendant [value] quand elle en a un.
///
/// Le dialogue est posé sur le navigateur racine : les écrans vivent dans
/// une branche du shell, et une fermeture prise dans la branche ne fermerait
/// pas la boîte de dialogue.
void _closeDialog(BuildContext context, [Object? value]) {
  Navigator.of(context, rootNavigator: true).pop(value);
}
