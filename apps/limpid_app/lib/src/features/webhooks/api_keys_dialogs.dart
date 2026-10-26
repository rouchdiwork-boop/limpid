import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La demande de création d'une clé, telle que la fenêtre la rend.
final class ApiKeyDraft {
  /// Crée une demande.
  const ApiKeyDraft({required this.name, required this.scopes});

  /// Le nom donné à la clé.
  final String name;

  /// Le périmètre choisi.
  final Set<ApiKeyScope> scopes;
}

/// Ouvre la fenêtre qui crée une clé d'API.
///
/// La fenêtre rend la demande de l'auteur, ou `null` quand il renonce.
Future<ApiKeyDraft?> showApiKeyCreation(BuildContext context) {
  return showDialog<ApiKeyDraft>(
    context: context,
    builder: (BuildContext dialogContext) => const _CreateApiKeyDialog(),
  );
}

/// La fenêtre qui crée une clé d'API.
final class _CreateApiKeyDialog extends StatefulWidget {
  /// Crée la fenêtre.
  const _CreateApiKeyDialog();

  @override
  State<_CreateApiKeyDialog> createState() => _CreateApiKeyDialogState();
}

/// L'état de la fenêtre qui crée une clé.
final class _CreateApiKeyDialogState extends State<_CreateApiKeyDialog> {
  final TextEditingController _name = TextEditingController();

  /// Le périmètre choisi, la lecture par défaut.
  Set<ApiKeyScope> _scopes = <ApiKeyScope>{ApiKeyScope.read};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Ajoute le périmètre [scope] au choix, ou l'en retire.
  void _toggle(ApiKeyScope scope) {
    setState(() {
      final Set<ApiKeyScope> next = Set<ApiKeyScope>.of(_scopes);
      if (!next.remove(scope)) next.add(scope);
      _scopes = Set<ApiKeyScope>.unmodifiable(next);
    });
  }

  /// Rend la demande à l'écran.
  void _submit() {
    final String name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(ApiKeyDraft(name: name, scopes: _scopes));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope tokens = context.limpid;

    return LimpidDialog(
      title: strings.apiKeysCreate,
      icon: LimpidIcons.code,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        LimpidButton(
          label: strings.apiKeysCreate,
          onPressed: _name.text.trim().isEmpty ? null : _submit,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LimpidTextField(
            controller: _name,
            label: strings.apiKeysName,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (String _) => setState(() {}),
            onSubmitted: (String _) => _submit(),
          ),
          SizedBox(height: tokens.spacing.space16),
          Wrap(
            spacing: tokens.spacing.space8,
            runSpacing: tokens.spacing.space8,
            children: <Widget>[
              LimpidChip(
                label: strings.apiKeysScopeRead,
                isSelected: _scopes.contains(ApiKeyScope.read),
                onTap: () => _toggle(ApiKeyScope.read),
              ),
              LimpidChip(
                label: strings.apiKeysScopeWrite,
                isSelected: _scopes.contains(ApiKeyScope.write),
                onTap: () => _toggle(ApiKeyScope.write),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Demande à l'auteur de confirmer la suppression d'une clé.
///
/// La fenêtre rend `true` quand l'auteur confirme, `false` quand il
/// renonce.
Future<bool> showKeyDeletion(BuildContext context, String name) async {
  final AppLocalizations strings = AppLocalizations.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => LimpidDialog(
      title: strings.apiKeysDelete,
      icon: LimpidIcons.delete,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        LimpidButton(
          label: strings.apiKeysDelete,
          variant: LimpidButtonVariant.danger,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
      child: Text(
        name,
        style: LimpidTypography.monoStyle(
          color: dialogContext.limpid.colors.fgDefault,
        ),
      ),
    ),
  );
  return confirmed ?? false;
}
