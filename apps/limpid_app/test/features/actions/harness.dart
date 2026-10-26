import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';
import 'package:limpid_app/src/domain/webhook_repository.dart';
import 'package:limpid_app/src/features/billing/billing_actions.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_actions.dart';
import 'package:limpid_app/src/features/teams/teams_actions.dart';
import 'package:limpid_app/src/features/webhooks/webhooks_screen.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Gives the test a viewport of the size it needs.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Wraps [home] in a provider scope holding the ports of the test.
///
/// The application of the test carries the theme and the strings of the real
/// application: the screens read them.
Widget actionHarness({
  required Widget home,
  TwoFactorRepository? twoFactor,
  ExportRepository? exports,
  GdprRepository? gdpr,
  PlanRepository? plans,
  TeamRepository? teams,
  KdpRepository? kdp,
  AiRepository? ai,
  ManuscriptRepository? manuscripts,
}) {
  return ProviderScope(
    overrides: [
      if (twoFactor != null)
        twoFactorRepositoryProvider.overrideWithValue(twoFactor),
      if (exports != null) exportRepositoryProvider.overrideWithValue(exports),
      if (gdpr != null) gdprRepositoryProvider.overrideWithValue(gdpr),
      if (plans != null) planRepositoryProvider.overrideWithValue(plans),
      if (teams != null) teamRepositoryProvider.overrideWithValue(teams),
      if (kdp != null) kdpRepositoryProvider.overrideWithValue(kdp),
      if (ai != null) aiRepositoryProvider.overrideWithValue(ai),
      if (manuscripts != null)
        manuscriptRepositoryProvider.overrideWithValue(manuscripts),
    ],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

/// Wraps the screen of the webhooks in a provider scope holding the ports of
/// the test.
Widget webhooksActionHarness({
  required WebhookRepository repository,
  required TwoFactorRepository twoFactor,
}) {
  return ProviderScope(
    overrides: [
      webhookRepositoryProvider.overrideWithValue(repository),
      twoFactorRepositoryProvider.overrideWithValue(twoFactor),
    ],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const WebhooksScreen(),
    ),
  );
}

/// The screen that chooses a plan.
///
/// The screen calls the very action of the billing screen: the call site the
/// test wants to guard is the one the screen of the application uses.
class BillingActionScreen extends ConsumerWidget {
  /// Creates the screen.
  const BillingActionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: LimpidButton(
          label: 'choisir',
          onPressed: () => unawaited(
            choosePlan(
              context,
              ref,
              SubscriptionPlan.writer,
              BillingPeriod.monthly,
            ),
          ),
        ),
      ),
    );
  }
}

/// The screen that changes the role of a member of a team.
///
/// The screen calls the very action of the page of a team.
class TeamActionScreen extends ConsumerWidget {
  /// Creates the screen.
  const TeamActionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: LimpidButton(
          label: 'changer',
          onPressed: () => unawaited(
            changeMemberRole(
              context,
              ref,
              teamId: 'team-1',
              member: TeamMember(
                teamId: 'team-1',
                userId: 'member-2',
                role: TeamRole.coAuthor,
                createdAt: DateTime.utc(2026, 11, 1),
              ),
              role: TeamRole.reader,
            ),
          ),
        ),
      ),
    );
  }
}

/// The screen that deposits a publication dossier.
///
/// The screen calls the very action of the page of a dossier.
class KdpActionScreen extends ConsumerWidget {
  /// Creates the screen.
  const KdpActionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: LimpidButton(
          label: 'déposer',
          onPressed: () =>
              unawaited(depositKdpSubmission(context, ref, 'submission-1')),
        ),
      ),
    );
  }
}

/// The screen that writes in the manuscript of the author.
///
/// The write is **local**: the device keeps the manuscript, and the server
/// learns about it through the synchronisation. The action is not wrapped.
class LocalActionScreen extends ConsumerWidget {
  /// Creates the screen.
  const LocalActionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: LimpidButton(
          label: 'écrire',
          onPressed: () => unawaited(_write(ref)),
        ),
      ),
    );
  }

  /// Writes in the manuscript of the author.
  ///
  /// The failure is caught here: the screen says it. The window of the
  /// second factor never opens — the write is local.
  Future<void> _write(WidgetRef ref) async {
    try {
      await ref.read(manuscriptRepositoryProvider).saveProject(_project);
    } on Object {
      return;
    }
  }

  /// The manuscript the author writes in.
  static const Project _project = Project(
    id: ProjectId('project-1'),
    ownerId: AuthorId('auteur-1'),
    title: 'Les Heures de Cendre',
    synopsis: 'Un livre sur le sel et la marée.',
    status: ManuscriptStatus.draft,
    order: OrderKey.initial,
  );
}
