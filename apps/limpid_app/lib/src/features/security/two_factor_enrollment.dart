import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Le parcours d'activation de la double authentification.
///
/// Le panneau inscrit le compte, montre le secret, demande le premier code,
/// puis affiche les codes de récupération — **une seule fois**. Les codes ne
/// sont jamais écrits : quand l'auteur quitte le panneau, ils sont perdus.
class TwoFactorEnrollmentPanel extends ConsumerStatefulWidget {
  /// Crée le panneau.
  const TwoFactorEnrollmentPanel({
    super.key,
    this.onCompleted,
    this.onCancelled,
  });

  /// Appelé quand l'auteur a confirmé l'inscription.
  final VoidCallback? onCompleted;

  /// Appelé quand l'auteur renonce à activer la double authentification.
  final VoidCallback? onCancelled;

  @override
  ConsumerState<TwoFactorEnrollmentPanel> createState() =>
      _TwoFactorEnrollmentPanelState();
}

/// L'état du parcours d'activation.
final class _TwoFactorEnrollmentPanelState
    extends ConsumerState<TwoFactorEnrollmentPanel> {
  final TextEditingController _code = TextEditingController();

  /// L'inscription en cours, `null` quand elle n'a pas encore abouti.
  TwoFactorEnrollment? _enrollment;

  /// Les codes de récupération, `null` tant que l'inscription n'est pas
  /// confirmée.
  List<String>? _recoveryCodes;

  /// Une opération est-elle en cours ?
  bool _isBusy = true;

  /// Le message d'erreur, `null` quand rien n'a échoué.
  String? _error;

  @override
  void initState() {
    super.initState();
    _enroll();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Inscrit le compte et garde le secret.
  ///
  /// L'appel ne touche pas à l'état avant la réponse du serveur : le
  /// panneau est déjà en attente quand il s'ouvre, et une relance passe par
  /// le bouton d'échec.
  Future<void> _enroll() async {
    try {
      final TwoFactorEnrollment enrollment = await ref
          .read(twoFactorRepositoryProvider)
          .enroll();
      if (!mounted) return;
      setState(() {
        _enrollment = enrollment;
        _isBusy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      // Les chaînes sont lues ici : le panneau vient d'être construit, la
      // recherche des localisations y serait encore interdite.
      final AppLocalizations strings = AppLocalizations.of(context);
      setState(() {
        _isBusy = false;
        _error = _messageOf(error, strings);
      });
    }
  }

  /// Confirme l'inscription avec le premier code de l'auteur.
  Future<void> _confirm() async {
    final String code = _code.text.trim();
    if (code.isEmpty || _isBusy) return;

    final AppLocalizations strings = AppLocalizations.of(context);

    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final List<String> codes = await ref
          .read(twoFactorRepositoryProvider)
          .confirm(code: code);
      if (!mounted) return;
      setState(() {
        _recoveryCodes = codes;
        _isBusy = false;
      });
      widget.onCompleted?.call();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _error = _messageOf(error, strings);
      });
    }
  }

  /// Copie les codes de récupération dans le presse-papiers.
  Future<void> _copy() async {
    final List<String>? codes = _recoveryCodes;
    if (codes == null) return;
    final AppLocalizations strings = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: codes.join('\n')));
    if (!mounted) return;
    LimpidSnackbar.show(
      context,
      message: strings.twoFactorRecoveryIntro,
      variant: LimpidStatusVariant.success,
    );
  }

  /// Le message que l'auteur lit quand l'opération a échoué.
  static String _messageOf(Object error, AppLocalizations strings) {
    if (error is ApiUnauthorizedException) return strings.twoFactorInvalidCode;
    if (error is ApiValidationException) return strings.twoFactorInvalidCode;
    if (error is ServiceUnavailableException) {
      return strings.twoFactorUnavailable;
    }
    return strings.errorGeneric;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final List<String>? codes = _recoveryCodes;

    if (codes != null) {
      return _recoveryCodesPanel(context, strings, scope, codes);
    }

    if (_enrollment == null) {
      return _failure(context, strings, scope);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _secretPanel(context, strings, scope, _enrollment!),
        SizedBox(height: scope.spacing.space16),
        LimpidTextField(
          controller: _code,
          errorText: _error,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _confirm(),
        ),
        SizedBox(height: scope.spacing.space16),
        LimpidButton(
          label: strings.twoFactorConfirm,
          loading: _isBusy,
          expand: true,
          onPressed: _confirm,
        ),
        SizedBox(height: scope.spacing.space8),
        LimpidButton(
          label: strings.actionCancel,
          variant: LimpidButtonVariant.ghost,
          expand: true,
          onPressed: widget.onCancelled,
        ),
      ],
    );
  }

  /// Le panneau qui montre le secret et l'adresse d'inscription.
  Widget _secretPanel(
    BuildContext context,
    AppLocalizations strings,
    LimpidThemeScope scope,
    TwoFactorEnrollment enrollment,
  ) {
    return LimpidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            strings.twoFactorSecretIntro,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
          ),
          SizedBox(height: scope.spacing.space16),
          Text(
            strings.twoFactorSecretLabel,
            style: LimpidTypography.labelStyle(color: scope.colors.fgMuted),
          ),
          SizedBox(height: scope.spacing.space8),
          SelectableText(
            enrollment.secret,
            style: LimpidTypography.monoStyle(color: scope.colors.fgDefault),
          ),
          SizedBox(height: scope.spacing.space12),
          SelectableText(
            enrollment.otpauthUrl,
            style: LimpidTypography.monoStyle(color: scope.colors.fgMuted),
          ),
        ],
      ),
    );
  }

  /// Le panneau qui montre les codes de récupération, une seule fois.
  Widget _recoveryCodesPanel(
    BuildContext context,
    AppLocalizations strings,
    LimpidThemeScope scope,
    List<String> codes,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LimpidCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                strings.twoFactorRecoveryCodes,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scope.colors.fgDefault,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: scope.spacing.space8),
              Text(
                strings.twoFactorRecoveryIntro,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
              ),
              SizedBox(height: scope.spacing.space16),
              for (final String code in codes)
                Padding(
                  padding: EdgeInsets.only(bottom: scope.spacing.space4),
                  child: SelectableText(
                    code,
                    style: LimpidTypography.monoStyle(
                      color: scope.colors.fgDefault,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: scope.spacing.space16),
        LimpidButton(
          label: strings.actionSave,
          icon: LimpidIcons.check,
          expand: true,
          onPressed: _copy,
        ),
        SizedBox(height: scope.spacing.space8),
        LimpidButton(
          label: strings.actionContinue,
          variant: LimpidButtonVariant.ghost,
          expand: true,
          onPressed: widget.onCancelled,
        ),
      ],
    );
  }

  /// Le panneau d'échec de l'inscription.
  Widget _failure(
    BuildContext context,
    AppLocalizations strings,
    LimpidThemeScope scope,
  ) {
    if (_isBusy) {
      return const Center(child: LimpidSpinner());
    }
    return LimpidEmptyState(
      title: strings.errorGeneric,
      message: _error,
      icon: LimpidIcons.error,
      action: LimpidButton(
        label: strings.actionRetry,
        onPressed: () {
          setState(() {
            _isBusy = true;
            _error = null;
          });
          _enroll();
        },
      ),
    );
  }
}
