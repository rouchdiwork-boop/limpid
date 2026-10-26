import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Demande un code de second facteur à l'auteur et le vérifie.
///
/// Le code est un code à six chiffres ou un code de récupération : le
/// serveur sait dire lequel est le bon. La fenêtre renvoie la preuve
/// obtenue, ou `null` quand l'auteur renonce.
Future<TwoFactorProof?> showTwoFactorCodeDialog(BuildContext context) {
  return showDialog<TwoFactorProof>(
    context: context,
    builder: (BuildContext dialogContext) => const _TwoFactorCodeDialog(),
  );
}

/// La fenêtre qui demande un code de second facteur.
final class _TwoFactorCodeDialog extends ConsumerStatefulWidget {
  /// Crée la fenêtre.
  const _TwoFactorCodeDialog();

  @override
  ConsumerState<_TwoFactorCodeDialog> createState() =>
      _TwoFactorCodeDialogState();
}

/// L'état de la fenêtre qui demande un code.
final class _TwoFactorCodeDialogState
    extends ConsumerState<_TwoFactorCodeDialog> {
  final TextEditingController _code = TextEditingController();

  /// La vérification est-elle en cours ?
  bool _isBusy = false;

  /// Le message d'erreur, `null` quand le code n'a pas encore été refusé.
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Vérifie le code saisi et ferme la fenêtre avec la preuve.
  Future<void> _verify() async {
    final String code = _code.text.trim();
    if (code.isEmpty || _isBusy) return;

    final AppLocalizations strings = AppLocalizations.of(context);

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      final TwoFactorProof proof = await ref
          .read(twoFactorRepositoryProvider)
          .verify(code: code);
      if (!mounted) return;
      Navigator.of(context).pop(proof);
    } on ApiUnauthorizedException {
      _fail(strings.twoFactorInvalidCode);
    } on ApiValidationException {
      _fail(strings.twoFactorInvalidCode);
    } on Object {
      _fail(strings.errorGeneric);
    }
  }

  /// Affiche le message d'erreur [message] dans la fenêtre.
  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return LimpidDialog(
      title: strings.twoFactorTitle,
      icon: LimpidIcons.user,
      actions: <Widget>[
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        LimpidButton(
          label: strings.twoFactorVerify,
          loading: _isBusy,
          onPressed: _verify,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            strings.twoFactorProofMissing,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
          ),
          SizedBox(height: scope.spacing.space16),
          LimpidTextField(
            controller: _code,
            errorText: _error,
            autofocus: true,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.text,
            onSubmitted: (_) => _verify(),
          ),
        ],
      ),
    );
  }
}
