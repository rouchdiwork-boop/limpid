import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/features/teams/teams_actions.dart';
import 'package:limpid_app/src/features/teams/teams_providers.dart';
import 'package:limpid_app/src/features/teams/teams_routes.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// L'écran des équipes du compte.
///
/// L'écran montre les équipes dont le compte est membre et le bouton qui en
/// crée une. Il ne montre jamais une équipe qu'il n'a pas lue : quand le
/// service des équipes n'est pas configuré, il le dit.
class TeamsScreen extends ConsumerWidget {
  /// Crée l'écran.
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<List<Team>> teams = ref.watch(teamsProvider);
    final bool isAvailable =
        ref.watch(teamRepositoryProvider) is! UnavailableService;

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
                title: strings.demoModeTitle,
                message: strings.demoModeMessage,
              )
            else
              _list(context, ref, strings, teams),
            SizedBox(height: scope.spacing.space32),
            LimpidButton(
              label: strings.teamsCreate,
              icon: LimpidIcons.add,
              expand: true,
              onPressed: isAvailable ? () => createTeam(context, ref) : null,
            ),
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
          strings.teamsTitle,
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
            strings.teamsSubtitle,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: scope.colors.fgMuted),
          ),
        ),
      ],
    );
  }

  /// La liste des équipes, une fois le serveur lu.
  Widget _list(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations strings,
    AsyncValue<List<Team>> teams,
  ) {
    return teams.when(
      loading: () => const Center(child: LimpidSpinner()),
      error: (Object error, StackTrace stack) =>
          _failure(context, ref, strings, error),
      data: (List<Team> list) => list.isEmpty
          ? LimpidEmptyState(
              title: strings.teamsEmpty,
              action: LimpidButton(
                label: strings.teamsCreate,
                onPressed: () => createTeam(context, ref),
              ),
            )
          : Column(
              children: <Widget>[
                for (final Team team in list) _tile(context, team),
              ],
            ),
    );
  }

  /// La carte d'une équipe.
  Widget _tile(BuildContext context, Team team) {
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.only(bottom: scope.spacing.space12),
      child: LimpidCard(
        padding: EdgeInsets.zero,
        onTap: () => openTeam(context, team),
        child: LimpidListTile(
          title: team.name,
          leading: const Icon(LimpidIcons.list),
          trailing: const Icon(LimpidIcons.chevronRight),
        ),
      ),
    );
  }

  /// L'état d'échec de la lecture des équipes.
  Widget _failure(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations strings,
    Object error,
  ) {
    if (isTeamServiceMissing(error)) {
      return LimpidBanner(
        variant: LimpidStatusVariant.info,
        title: strings.demoModeTitle,
        message: strings.demoModeMessage,
      );
    }
    return LimpidEmptyState(
      title: teamFailureMessage(strings, error),
      icon: LimpidIcons.error,
      action: LimpidButton(
        label: strings.actionRetry,
        onPressed: () => ref.invalidate(teamsProvider),
      ),
    );
  }
}

/// Ouvre l'équipe [team].
///
/// La route est déclarée par le routeur de l'application : l'écran ne
/// construit pas sa navigation.
void openTeam(BuildContext context, Team team) {
  context.push(TeamsRoutes.detail(team.id));
}
