import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_actions.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_providers.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_routes.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_states.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'écran d'un dépôt de publication.
///
/// L'écran montre l'état du dépôt, les problèmes du contrôle de soumission et
/// le motif d'un refus d'Amazon : un refus que l'auteur ne peut pas lire
/// n'est pas un refus qu'il peut corriger.
///
/// Deux actions : déposer le dossier chez Amazon, ou corriger ses
/// métadonnées et réessayer.
class KdpSubmissionScreen extends ConsumerWidget {
  /// Crée l'écran.
  const KdpSubmissionScreen({required this.submissionId, super.key});

  /// L'identifiant du dépôt montré.
  final String submissionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final AsyncValue<KdpSubmission?> submission = ref.watch(
      kdpSubmissionProvider(submissionId),
    );
    final KdpDepositState deposit = ref.watch(kdpDepositProvider);

    return Scaffold(
      body: SafeArea(
        child: submission.when(
          data: (KdpSubmission? found) {
            if (found == null) return _missing(context, strings);
            return _detail(context, ref, strings, found, deposit);
          },
          loading: () =>
              const Center(child: LimpidSpinner(size: LimpidSpinnerSize.large)),
          error: (Object error, StackTrace stack) => KdpFailureState(
            error: error,
            onRetry: () => ref.invalidate(kdpSubmissionProvider(submissionId)),
          ),
        ),
      ),
    );
  }

  /// L'état d'un dépôt que le serveur ne connaît pas.
  Widget _missing(BuildContext context, AppLocalizations strings) {
    final LimpidThemeScope scope = context.limpid;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: strings.errorGeneric,
        icon: LimpidIcons.error,
        action: LimpidButton(
          label: strings.kdpTitle,
          icon: LimpidIcons.arrowLeft,
          onPressed: () => context.go(KdpRoutes.screen),
        ),
      ),
    );
  }

  /// Le dossier, son état et les actions qui le font avancer.
  Widget _detail(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations strings,
    KdpSubmission submission,
    KdpDepositState deposit,
  ) {
    final LimpidThemeScope scope = context.limpid;
    final Object? failure = _failureOf(deposit, submission);

    return ListView(
      padding: EdgeInsets.all(scope.spacing.space24),
      children: <Widget>[
        _header(context, strings, submission),
        SizedBox(height: scope.spacing.space16),
        if (failure != null) ...<Widget>[
          _failure(context, strings, failure),
          SizedBox(height: scope.spacing.space16),
        ],
        if (submission.refusal != null) ...<Widget>[
          _refusal(context, strings, submission.refusal!),
          SizedBox(height: scope.spacing.space16),
        ],
        if (submission.issues.isNotEmpty) ...<Widget>[
          _issues(context, strings, submission.issues),
          SizedBox(height: scope.spacing.space16),
        ],
        _metadata(context, strings, submission),
        SizedBox(height: scope.spacing.space24),
        _actions(context, ref, strings, submission, deposit),
      ],
    );
  }

  /// Le titre du livre, son état et le retour à la liste.
  Widget _header(
    BuildContext context,
    AppLocalizations strings,
    KdpSubmission submission,
  ) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            LimpidIconButton(
              icon: LimpidIcons.arrowLeft,
              tooltip: strings.kdpTitle,
              onPressed: () => context.go(KdpRoutes.screen),
            ),
            SizedBox(width: scope.spacing.space8),
            Expanded(
              child: Text(
                submission.title,
                style: textTheme.headlineSmall?.copyWith(
                  color: scope.colors.fgDefault,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: scope.spacing.space8),
            LimpidBadge(
              label: kdpStateLabel(strings, submission.state),
              variant: kdpStateVariant(submission.state),
            ),
          ],
        ),
        SizedBox(height: scope.spacing.space8),
        Text(
          submission.author,
          style: textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
        ),
      ],
    );
  }

  /// L'échec du dépôt, quand il y en a eu un.
  Widget _failure(
    BuildContext context,
    AppLocalizations strings,
    Object error,
  ) {
    if (error is KdpUnavailableException) {
      return KdpNotConfiguredBanner(reason: error.reason);
    }
    if (error is ServiceUnavailableException) {
      return const KdpNotConfiguredBanner();
    }
    return LimpidBanner(
      variant: LimpidStatusVariant.danger,
      title: strings.errorGeneric,
      message: error is ApiException ? error.message : null,
    );
  }

  /// Le refus d'Amazon et le motif qu'il porte.
  Widget _refusal(
    BuildContext context,
    AppLocalizations strings,
    KdpRefusal refusal,
  ) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return LimpidCard(
      title: strings.kdpRefused,
      leading: const Icon(LimpidIcons.warning),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (refusal.reason != null) ...<Widget>[
            Text(
              refusal.reason!,
              style: textTheme.bodyMedium?.copyWith(
                color: scope.colors.fgDefault,
              ),
            ),
            SizedBox(height: scope.spacing.space8),
          ],
          if (refusal.issues.isNotEmpty) ...<Widget>[
            Text(
              strings.kdpRefusedReason,
              style: textTheme.labelLarge?.copyWith(
                color: scope.colors.fgMuted,
              ),
            ),
            SizedBox(height: scope.spacing.space8),
            for (final KdpIssue issue in refusal.issues)
              Padding(
                padding: EdgeInsets.only(bottom: scope.spacing.space8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      issue.isBlocking
                          ? LimpidIcons.danger
                          : LimpidIcons.warning,
                      size: 16,
                      color: scope.colors.fgMuted,
                    ),
                    SizedBox(width: scope.spacing.space8),
                    Expanded(
                      child: Text(
                        issue.message,
                        style: textTheme.bodySmall?.copyWith(
                          color: scope.colors.fgDefault,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Les problèmes du contrôle de soumission.
  Widget _issues(
    BuildContext context,
    AppLocalizations strings,
    List<KdpIssue> issues,
  ) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return LimpidCard(
      title: strings.kdpFixAndRetry,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final KdpIssue issue in issues)
            Padding(
              padding: EdgeInsets.only(bottom: scope.spacing.space8),
              child: Text(
                issue.message,
                style: textTheme.bodySmall?.copyWith(
                  color: scope.colors.fgDefault,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Les métadonnées de la fiche produit.
  Widget _metadata(
    BuildContext context,
    AppLocalizations strings,
    KdpSubmission submission,
  ) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return LimpidCard(
      title: strings.projectMetadataTitle,
      leading: const Icon(LimpidIcons.book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _row(context, strings.kdpIsbn, submission.isbn ?? ''),
          _row(context, strings.kdpLanguage, submission.language),
          _row(context, strings.kdpKeywords, submission.keywords.join(', ')),
          _row(context, strings.kdpBisac, submission.categories.join(', ')),
          _row(context, strings.commonWords, formatCount(submission.wordCount)),
          if (submission.description.isNotEmpty) ...<Widget>[
            SizedBox(height: scope.spacing.space12),
            Text(
              submission.description,
              style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
            ),
          ],
        ],
      ),
    );
  }

  /// Une ligne de métadonnée.
  Widget _row(BuildContext context, String label, String value) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: scope.spacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: textTheme.labelMedium?.copyWith(
                color: scope.colors.fgMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodySmall?.copyWith(
                color: scope.colors.fgDefault,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Les actions du dossier.
  Widget _actions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations strings,
    KdpSubmission submission,
    KdpDepositState deposit,
  ) {
    final bool isRunning =
        deposit.isRunning && deposit.submissionId == submission.id;
    final LimpidThemeScope scope = context.limpid;

    return Wrap(
      spacing: scope.spacing.space12,
      runSpacing: scope.spacing.space12,
      children: <Widget>[
        if (submission.canDeposit)
          LimpidButton(
            label: strings.kdpSubmit,
            icon: LimpidIcons.upload,
            loading: isRunning,
            onPressed: () => depositKdpSubmission(context, ref, submission.id),
          ),
        if (submission.state == KdpState.refused ||
            submission.state == KdpState.failed)
          LimpidButton(
            label: strings.kdpFixAndRetry,
            icon: LimpidIcons.edit,
            variant: LimpidButtonVariant.secondary,
            onPressed: () => prepareKdpSubmission(
              context,
              ref,
              initial: submission,
              retry: true,
            ),
          ),
      ],
    );
  }

  /// L'erreur du dépôt, quand elle concerne ce dossier.
  Object? _failureOf(KdpDepositState deposit, KdpSubmission? submission) {
    final Object? error = deposit.error;
    if (error == null) return null;
    final String? id = deposit.submissionId;
    if (id == null) return error;
    if (submission != null && submission.id != id) return null;
    return error;
  }
}
