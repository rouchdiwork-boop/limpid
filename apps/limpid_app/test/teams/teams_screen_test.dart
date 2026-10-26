import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/features/teams/team_detail_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  group("l'écran des équipes", () {
    testWidgets('montre les équipes du compte', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(teamsHarness(repository: FakeTeamRepository()));
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamsStrings(tester);

      expect(find.text('La Brigade'), findsOneWidget);
      expect(find.text(strings.teamsTitle), findsOneWidget);
      expect(find.text(strings.teamsSubtitle), findsOneWidget);
    });

    testWidgets('montre l’état vide quand il n’y a pas d’équipe', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        teamsHarness(repository: FakeTeamRepository(teams: <Team>[])),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamsStrings(tester);

      expect(find.text(strings.teamsEmpty), findsOneWidget);
      expect(find.text('La Brigade'), findsNothing);
    });

    testWidgets('dit que le service n’est pas configuré', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(
        teamsHarness(repository: const UnavailableTeamRepository()),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamsStrings(tester);

      expect(find.text(strings.demoModeTitle), findsOneWidget);
      expect(find.text(strings.teamsEmpty), findsNothing);
    });

    testWidgets('crée une équipe et la montre dans la liste', (tester) async {
      useSurface(tester, const Size(900, 900));
      final FakeTeamRepository repository = FakeTeamRepository();
      await tester.pumpWidget(teamsHarness(repository: repository));
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamsStrings(tester);

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.teamsCreate).first,
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Les Éclaireurs');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(LimpidButton, strings.actionCreate));
      await tester.pumpAndSettle();

      expect(repository.createdNames, <String>['Les Éclaireurs']);
      expect(find.text('Les Éclaireurs'), findsOneWidget);
    });

    testWidgets('ouvre la page d’une équipe', (tester) async {
      useSurface(tester, const Size(900, 900));
      await tester.pumpWidget(teamsHarness(repository: FakeTeamRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('La Brigade'));
      await tester.pumpAndSettle();

      expect(find.byType(TeamDetailScreen), findsOneWidget);
      expect(find.text('member-2'), findsOneWidget);
    });
  });

  group("la page d'une équipe", () {
    testWidgets('montre les membres et leurs rôles', (tester) async {
      useSurface(tester, const Size(900, 1400));
      await tester.pumpWidget(
        teamDetailHarness(repository: FakeTeamRepository(), teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      expect(find.text('La Brigade'), findsOneWidget);
      expect(find.text('owner-1'), findsOneWidget);
      expect(find.text('member-2'), findsOneWidget);

      // Le rôle de chaque membre est porté par un badge.
      final Finder badges = find.byType(LimpidBadge);
      expect(
        find.descendant(
          of: badges,
          matching: find.text(strings.teamsRoleOwner),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: badges,
          matching: find.text(strings.teamsRoleCoauthor),
        ),
        findsOneWidget,
      );
    });

    testWidgets('compte les sièges occupés', (tester) async {
      useSurface(tester, const Size(900, 1400));
      await tester.pumpWidget(
        teamDetailHarness(repository: FakeTeamRepository(), teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      // Le propriétaire ne prend pas de siège : un membre invité sur cinq.
      // La chaîne attend le total avant l'usage : l'écran montre l'ordre
      // inverse, il se trompe.
      expect(find.text(strings.teamsSeatsUsed('5', '1')), findsOneWidget);
      expect(find.text(strings.teamsSeatsUsed('1', '5')), findsNothing);
    });

    testWidgets('avertit quand l’équipe n’a plus de siège', (tester) async {
      useSurface(tester, const Size(900, 1400));
      await tester.pumpWidget(
        teamDetailHarness(
          repository: FakeTeamRepository(),
          teamId: 'team-1',
          plans: FakePlanRepository(seatCount: 1),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      // Un membre invité pour un seul siège : l'équipe est pleine.
      expect(find.text(strings.teamsSeatFull), findsOneWidget);
    });

    testWidgets('compte les sièges sans limite quand la formule échoue', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1400));
      await tester.pumpWidget(
        teamDetailHarness(
          repository: FakeTeamRepository(),
          teamId: 'team-1',
          plans: const FailingPlanRepository(),
        ),
      );
      await tester.pumpAndSettle();

      // La formule ne dit pas la limite : l'écran ne montre pas de limite
      // qu'il n'a pas lue, il montre les sièges occupés.
      final AppLocalizations strings = teamStrings(tester);
      expect(find.text('1'), findsOneWidget);
      expect(find.text(strings.teamsSeatsUsed('5', '1')), findsNothing);
    });

    testWidgets('invite un membre et montre son rôle', (tester) async {
      useSurface(tester, const Size(900, 1400));
      final FakeTeamRepository repository = FakeTeamRepository();
      await tester.pumpWidget(
        teamDetailHarness(repository: repository, teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      await tester.tap(find.widgetWithText(LimpidButton, strings.teamsInvite));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'member-3');
      await tester.pumpAndSettle();

      final Finder dialog = find.byType(LimpidDialog);
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(LimpidButton, strings.teamsInvite),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.invitations, hasLength(1));
      expect(repository.invitations.first.userId, 'member-3');
      expect(repository.invitations.first.role, TeamRole.coAuthor);

      // L'invité rejoint l'équipe : son rôle apparaît dans la liste.
      expect(find.text('member-3'), findsOneWidget);
      expect(find.text(strings.teamsInviteSent), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('change le rôle d’un membre', (tester) async {
      useSurface(tester, const Size(900, 1400));
      final FakeTeamRepository repository = FakeTeamRepository();
      await tester.pumpWidget(
        teamDetailHarness(repository: repository, teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      final Finder select = find.byType(DropdownButton<TeamRole>);
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();

      await tester.tap(find.text(strings.teamsRoleBeta).last);
      await tester.pumpAndSettle();

      expect(repository.roleChanges, <(String, TeamRole)>[
        ('member-2', TeamRole.betaReader),
      ]);

      // Le badge du membre porte le nouveau rôle.
      expect(
        find.descendant(
          of: find.byType(LimpidBadge),
          matching: find.text(strings.teamsRoleBeta),
        ),
        findsOneWidget,
      );
    });

    testWidgets('retire un membre', (tester) async {
      useSurface(tester, const Size(900, 1400));
      final FakeTeamRepository repository = FakeTeamRepository();
      await tester.pumpWidget(
        teamDetailHarness(repository: repository, teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      await tester.tap(find.widgetWithText(LimpidButton, strings.teamsRemove));
      await tester.pumpAndSettle();

      expect(repository.removals, <String>['member-2']);
      expect(find.text('member-2'), findsNothing);
    });

    testWidgets('dit que l’équipe n’a plus de siège', (tester) async {
      useSurface(tester, const Size(900, 1400));
      final FakeTeamRepository repository = FakeTeamRepository()
        ..inviteError = const ApiValidationException(
          'La formule Studio est limitée à 5 sièges par équipe.',
          code: 'plan_limit_reached',
          statusCode: 402,
        );
      await tester.pumpWidget(
        teamDetailHarness(repository: repository, teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      await tester.tap(find.widgetWithText(LimpidButton, strings.teamsInvite));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'member-3');
      await tester.pumpAndSettle();

      final Finder dialog = find.byType(LimpidDialog);
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(LimpidButton, strings.teamsInvite),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(strings.teamsSeatFull), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('dit que le compte est déjà dans l’équipe', (tester) async {
      useSurface(tester, const Size(900, 1400));
      final FakeTeamRepository repository = FakeTeamRepository()
        ..inviteError = const ApiValidationException(
          'Ce compte fait déjà partie de l\'équipe.',
          code: 'conflict',
          statusCode: 409,
        );
      await tester.pumpWidget(
        teamDetailHarness(repository: repository, teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      await tester.tap(find.widgetWithText(LimpidButton, strings.teamsInvite));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'member-3');
      await tester.pumpAndSettle();

      final Finder dialog = find.byType(LimpidDialog);
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(LimpidButton, strings.teamsInvite),
        ),
      );
      await tester.pumpAndSettle();

      // Le refus du serveur est montré tel quel : l'écran ne prétend pas
      // que l'invitation est partie.
      expect(
        find.text('Ce compte fait déjà partie de l\'équipe.'),
        findsOneWidget,
      );
      expect(find.text(strings.teamsInviteSent), findsNothing);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('montre l’erreur quand l’équipe n’existe pas', (tester) async {
      useSurface(tester, const Size(900, 1400));
      final FakeTeamRepository repository = FakeTeamRepository()
        ..error = const ApiNotFoundException(
          'Cette équipe n’existe pas.',
          code: 'not_found',
          statusCode: 404,
        );
      await tester.pumpWidget(
        teamDetailHarness(repository: repository, teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      // L'erreur est montrée : l'écran ne montre pas une liste vide qui
      // laisserait croire que tout va bien.
      expect(find.text('Cette équipe n’existe pas.'), findsOneWidget);
      expect(find.text('member-2'), findsNothing);
    });

    testWidgets('laisse l’équipe quand l’auteur n’en est pas propriétaire', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1400));
      final FakeTeamRepository repository = FakeTeamRepository();
      await tester.pumpWidget(
        teamDetailHarness(
          repository: repository,
          teamId: 'team-1',
          session: const AuthSession(
            userId: 'member-2',
            email: 'coautrice@exemple.fr',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      // Un co-auteur ne peut ni inviter ni retirer les autres : il peut
      // quitter l'équipe.
      expect(
        find.widgetWithText(LimpidButton, strings.teamsLeave),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(LimpidButton, strings.teamsRemove),
        findsNothing,
      );

      await tester.tap(find.widgetWithText(LimpidButton, strings.teamsLeave));
      await tester.pumpAndSettle();

      expect(repository.removals, <String>['member-2']);
    });

    testWidgets('supprime l’équipe après la confirmation', (tester) async {
      useSurface(tester, const Size(900, 1400));
      final FakeTeamRepository repository = FakeTeamRepository();
      await tester.pumpWidget(
        teamDetailHarness(repository: repository, teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      await tester.tap(
        find.widgetWithText(LimpidButton, strings.apiKeysDelete),
      );
      await tester.pumpAndSettle();

      expect(find.text(strings.teamsDeleteConfirm), findsOneWidget);

      final Finder dialog = find.byType(LimpidDialog);
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(LimpidButton, strings.apiKeysDelete),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.deletions, <String>['team-1']);
    });
  });
}
