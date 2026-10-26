import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/admin_repository.dart';
import 'package:limpid_app/src/features/admin/admin_providers.dart';
import 'package:limpid_app/src/features/admin/admin_widgets.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La page d'un compte du back-office.
///
/// La page montre la formule du compte, son usage et les sièges que sa
/// formule accorde. Elle ne montre que ce que le serveur a publié : le
/// nombre de sièges vient du catalogue des formules, et la page ne l'affiche
/// pas quand le catalogue ne le dit pas.
class AdminAccountScreen extends ConsumerWidget {
  /// Crée la page d'un compte.
  const AdminAccountScreen({super.key, required this.accountId});

  /// L'identifiant du compte montré par la page.
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<AdminAccount> account = ref.watch(
      adminAccountProvider(accountId),
    );

    return Scaffold(
      body: SafeArea(
        child: account.when(
          loading: () => const Center(child: LimpidSpinner()),
          error: (Object error, StackTrace stack) => AdminFailureState(
            error: error,
            onRetry: () => ref.invalidate(adminAccountProvider(accountId)),
          ),
          data: (AdminAccount value) => ListView(
            padding: EdgeInsets.all(scope.spacing.space24),
            children: <Widget>[
              _identity(context, strings, value),
              SizedBox(height: scope.spacing.space16),
              _usage(context, strings, value),
              SizedBox(height: scope.spacing.space16),
              _plan(context, strings, ref, value),
            ],
          ),
        ),
      ),
    );
  }

  /// L'identité du compte : son identifiant, son adresse et sa formule.
  Widget _identity(
    BuildContext context,
    AppLocalizations strings,
    AdminAccount account,
  ) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String? email = account.email;
    final String? plan = account.plan;

    return LimpidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(LimpidIcons.user, size: 18),
              SizedBox(width: scope.spacing.space8),
              Expanded(
                child: Text(
                  account.userId,
                  style: textTheme.titleMedium?.copyWith(
                    color: scope.colors.fgDefault,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (account.isPurged)
                LimpidBadge(
                  label: strings.adminAccountPurged,
                  variant: LimpidStatusVariant.warning,
                ),
            ],
          ),
          if (email != null) ...<Widget>[
            SizedBox(height: scope.spacing.space4),
            Text(
              email,
              style: textTheme.bodyMedium?.copyWith(
                color: scope.colors.fgMuted,
              ),
            ),
          ],
          if (plan != null) ...<Widget>[
            SizedBox(height: scope.spacing.space12),
            LimpidBadge(label: plan, variant: LimpidStatusVariant.success),
          ],
        ],
      ),
    );
  }

  /// L'usage du compte : ses projets, ses collaborations, ses messages et ses
  /// opérations.
  Widget _usage(
    BuildContext context,
    AppLocalizations strings,
    AdminAccount account,
  ) {
    final LimpidThemeScope scope = context.limpid;

    return LimpidCard(
      child: Wrap(
        spacing: scope.spacing.space8,
        runSpacing: scope.spacing.space4,
        children: <Widget>[
          LimpidBadge(
            label: strings.adminAccountProjects(account.projectCount),
          ),
          LimpidBadge(
            label: strings.adminAccountCollaborations(
              account.collaborationCount,
            ),
          ),
          LimpidBadge(
            label: strings.adminAccountMessages(account.commentCount),
          ),
          LimpidBadge(
            label: strings.adminAccountOperations(account.operationCount),
          ),
        ],
      ),
    );
  }

  /// La formule du compte, les sièges qu'elle accorde et sa dernière
  /// activité.
  Widget _plan(
    BuildContext context,
    AppLocalizations strings,
    WidgetRef ref,
    AdminAccount account,
  ) {
    final AsyncValue<Map<String, int>> seats = ref.watch(
      adminPlanSeatsProvider,
    );
    final String? plan = account.plan;
    final int? seatCount = plan == null ? null : seats.value?[plan];

    return LimpidCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _row(
            context,
            strings.adminColumnPlan,
            plan ?? strings.adminUnknownPlan,
          ),
          if (seatCount != null)
            _row(context, strings.adminAccountSeats, '$seatCount'),
          _row(
            context,
            strings.adminAccountLastActivity,
            _lastActivity(context, strings, account),
          ),
        ],
      ),
    );
  }

  /// Une ligne de la page : une étiquette et sa valeur.
  Widget _row(BuildContext context, String label, String value) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: scope.colors.fgMuted,
              ),
            ),
          ),
          SizedBox(width: scope.spacing.space12),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              color: scope.colors.fgDefault,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// L'instant de la dernière activité du compte.
  String _lastActivity(
    BuildContext context,
    AppLocalizations strings,
    AdminAccount account,
  ) {
    final DateTime? moment = account.lastActivityAt;
    if (moment == null) return strings.adminNever;
    final MaterialLocalizations material = MaterialLocalizations.of(context);
    return '${material.formatMediumDate(moment)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(moment))}';
  }
}
