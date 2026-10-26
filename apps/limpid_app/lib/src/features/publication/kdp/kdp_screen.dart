import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_actions.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_providers.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_routes.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_states.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'écran des dépôts Amazon KDP du compte.
///
/// L'écran montre les dépôts que l'auteur a préparés, l'état de chacun et
/// le bouton qui en prépare un nouveau. Le vide a son état : l'auteur n'a
/// encore rien déposé, et l'écran lui dit ce qu'il peut faire.
class KdpScreen extends ConsumerWidget {
  /// Crée l'écran.
  const KdpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<List<KdpSubmission>> submissions = ref.watch(
      kdpSubmissionsProvider,
    );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(scope.spacing.space24),
          children: <Widget>[
            _header(context, strings),
            SizedBox(height: scope.spacing.space16),
            Align(
              alignment: Alignment.centerRight,
              child: LimpidButton(
                label: strings.kdpCreate,
                icon: LimpidIcons.add,
                onPressed: () => prepareKdpSubmission(context, ref),
              ),
            ),
            SizedBox(height: scope.spacing.space16),
            ..._submissions(context, ref, strings, submissions),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.kdpTitle,
          style: textTheme.headlineMedium?.copyWith(
            color: scope.colors.fgDefault,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: scope.spacing.space8),
        Text(
          strings.kdpSubtitle,
          style: textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
        ),
      ],
    );
  }

  /// Les dépôts du compte, ou l'état qui les remplace.
  List<Widget> _submissions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations strings,
    AsyncValue<List<KdpSubmission>> submissions,
  ) {
    final LimpidThemeScope scope = context.limpid;
    return submissions.when(
      data: (List<KdpSubmission> list) {
        if (list.isEmpty) {
          return <Widget>[
            KdpEmptyState(onCreate: () => prepareKdpSubmission(context, ref)),
          ];
        }
        return <Widget>[
          for (final KdpSubmission submission in list)
            Padding(
              padding: EdgeInsets.only(bottom: scope.spacing.space12),
              child: _tile(context, submission),
            ),
        ];
      },
      loading: () => <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
          child: const Center(
            child: LimpidSpinner(size: LimpidSpinnerSize.large),
          ),
        ),
      ],
      error: (Object error, StackTrace stack) => <Widget>[
        KdpFailureState(
          error: error,
          onRetry: () => ref.invalidate(kdpSubmissionsProvider),
        ),
      ],
    );
  }

  /// La fiche d'un dépôt.
  Widget _tile(BuildContext context, KdpSubmission submission) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final List<String> details = <String>[];
    final String? isbn = submission.isbn;
    if (isbn != null && isbn.isNotEmpty) {
      details.add('${strings.kdpIsbn} $isbn');
    }
    details.add(strings.libraryWords(formatCount(submission.wordCount)));

    return LimpidCard(
      title: submission.title,
      subtitle: submission.author,
      leading: const Icon(LimpidIcons.book),
      trailing: LimpidBadge(
        label: kdpStateLabel(strings, submission.state),
        variant: kdpStateVariant(submission.state),
      ),
      child: Text(
        details.join(' · '),
        style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
      ),
      onTap: () => context.push(KdpRoutes.submission(submission.id)),
    );
  }
}
