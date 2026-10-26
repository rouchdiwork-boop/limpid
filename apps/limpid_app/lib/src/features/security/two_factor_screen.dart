import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/auth/two_factor_proof_holder.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';
import 'package:limpid_app/src/features/security/security_providers.dart';
import 'package:limpid_app/src/features/security/two_factor_dialogs.dart';
import 'package:limpid_app/src/features/security/two_factor_enrollment.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'écran de la double authentification.
///
/// L'écran montre l'état du second facteur du compte : désactivé, activé, ou
/// exigé par la formule sans être activé. Il ouvre l'inscription, vérifie un
/// code et désactive le second facteur.
class TwoFactorScreen extends ConsumerStatefulWidget {
  /// Crée l'écran.
  const TwoFactorScreen({super.key});

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

/// L'état de l'écran de la double authentification.
final class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  /// Le parcours d'inscription est-il ouvert ?
  bool _isEnrolling = false;

  /// Vérifie un code et garde la preuve de la session.
  Future<void> _verify(BuildContext context) async {
    final AppLocalizations strings = AppLocalizations.of(context);
    final TwoFactorProof? proof = await showTwoFactorCodeDialog(context);
    if (proof == null) return;
    if (!context.mounted) return;
    TwoFactorProofHolder.set(proof);
    LimpidSnackbar.show(
      context,
      message: strings.twoFactorEnabled,
      variant: LimpidStatusVariant.success,
    );
  }

  /// Désactive le second facteur du compte.
  Future<void> _disable(BuildContext context) async {
    final AppLocalizations strings = AppLocalizations.of(context);
    try {
      await ref.read(twoFactorRepositoryProvider).disable();
    } on Object {
      if (!context.mounted) return;
      LimpidSnackbar.show(
        context,
        message: strings.errorGeneric,
        variant: LimpidStatusVariant.danger,
      );
      return;
    }
    TwoFactorProofHolder.clear();
    ref.invalidate(twoFactorStatusProvider);

    // La carte montre le nouvel état : l'auteur voit la double
    // authentification se désactiver.
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    // La preuve appartient à la session : elle tombe quand la session se
    // ferme.
    ref.watch(twoFactorSessionProvider);
    final bool isAvailable =
        ref.watch(twoFactorRepositoryProvider) is! UnavailableService;
    final AsyncValue<TwoFactorStatus> status = ref.watch(
      twoFactorStatusProvider,
    );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(scope.spacing.space24),
          children: <Widget>[
            _header(context, strings),
            SizedBox(height: scope.spacing.space24),
            if (!isAvailable)
              LimpidBanner(
                variant: LimpidStatusVariant.info,
                title: strings.twoFactorUnavailable,
              )
            else if (_isEnrolling)
              TwoFactorEnrollmentPanel(
                onCompleted: () {
                  ref.invalidate(twoFactorStatusProvider);
                  if (!context.mounted) return;
                  LimpidSnackbar.show(
                    context,
                    message: strings.twoFactorEnabled,
                    variant: LimpidStatusVariant.success,
                  );
                },
                onCancelled: () => setState(() => _isEnrolling = false),
              )
            else
              _state(context, strings, status),
          ],
        ),
      ),
    );
  }

  /// Le titre et la phrase d'introduction de la page.
  Widget _header(BuildContext context, AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      children: <Widget>[
        Text(
          strings.twoFactorTitle,
          textAlign: TextAlign.center,
          style: textTheme.headlineMedium?.copyWith(
            color: scope.colors.fgDefault,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: scope.spacing.space8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            strings.twoFactorSubtitle,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
          ),
        ),
      ],
    );
  }

  /// L'état du second facteur et les actions qui le changent.
  Widget _state(
    BuildContext context,
    AppLocalizations strings,
    AsyncValue<TwoFactorStatus> status,
  ) {
    return status.when(
      loading: () => const Center(child: LimpidSpinner()),
      error: (Object error, StackTrace stack) =>
          _failure(context, strings, error),
      data: (TwoFactorStatus data) => _details(context, strings, data),
    );
  }

  /// L'état du second facteur, une fois lu.
  Widget _details(
    BuildContext context,
    AppLocalizations strings,
    TwoFactorStatus data,
  ) {
    final LimpidThemeScope scope = context.limpid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (data.needsActivation) ...<Widget>[
          LimpidBanner(
            variant: LimpidStatusVariant.warning,
            title: strings.twoFactorRequired,
          ),
          SizedBox(height: scope.spacing.space16),
        ],
        LimpidCard(
          child: LimpidListTile(
            title: data.enabled
                ? strings.twoFactorStateOn
                : strings.twoFactorStateOff,
            leading: Icon(
              data.enabled ? LimpidIcons.check : LimpidIcons.offline,
            ),
          ),
        ),
        SizedBox(height: scope.spacing.space16),
        if (data.enabled) ...<Widget>[
          LimpidButton(
            label: strings.twoFactorVerify,
            expand: true,
            onPressed: () => _verify(context),
          ),
          SizedBox(height: scope.spacing.space8),
          LimpidButton(
            label: strings.twoFactorDisable,
            variant: LimpidButtonVariant.danger,
            expand: true,
            onPressed: () => _disable(context),
          ),
        ] else
          LimpidButton(
            label: strings.twoFactorEnable,
            expand: true,
            onPressed: () => setState(() => _isEnrolling = true),
          ),
      ],
    );
  }

  /// L'état d'échec de la lecture de l'état du compte.
  Widget _failure(
    BuildContext context,
    AppLocalizations strings,
    Object error,
  ) {
    if (error is ServiceUnavailableException) {
      return LimpidBanner(
        variant: LimpidStatusVariant.info,
        title: strings.twoFactorUnavailable,
      );
    }
    return LimpidEmptyState(
      title: strings.errorGeneric,
      icon: LimpidIcons.error,
      action: LimpidButton(
        label: strings.actionRetry,
        onPressed: () => ref.invalidate(twoFactorStatusProvider),
      ),
    );
  }
}
