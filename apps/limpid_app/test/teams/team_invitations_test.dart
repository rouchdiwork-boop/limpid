import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';
import 'harness.dart';

/// L'invitation en attente que l'écran montre.
TeamEmailInvitation _pendingInvitation({
  String email = 'invite@exemple.fr',
  TeamInvitationStatus status = TeamInvitationStatus.pending,
}) {
  return TeamEmailInvitation(
    id: 'invitation-1',
    teamId: 'team-1',
    email: email,
    role: TeamRole.coAuthor,
    status: status,
    invitedBy: 'owner-1',
    createdAt: fakeMoment,
    expiresAt: fakeMoment.add(const Duration(days: 7)),
  );
}

void main() {
  group('les invitations d\'équipe', () {
    testWidgets('montre l\'invitation en attente et son état', (tester) async {
      useSurface(tester, const Size(900, 1600));
      final FakeTeamRepository repository = FakeTeamRepository();
      repository.emailInvitations = <String, List<TeamEmailInvitation>>{
        'team-1': <TeamEmailInvitation>[_pendingInvitation()],
      };

      await tester.pumpWidget(
        teamDetailHarness(repository: repository, teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      expect(find.text('invite@exemple.fr'), findsOneWidget);
      expect(find.text(strings.webhooksDeliveryPending), findsOneWidget);
      expect(find.text(strings.teamsRoleCoauthor), findsWidgets);
    });

    testWidgets('montre une invitation expirée avec son échéance', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1600));
      final FakeTeamRepository repository = FakeTeamRepository();
      repository.emailInvitations = <String, List<TeamEmailInvitation>>{
        'team-1': <TeamEmailInvitation>[
          _pendingInvitation(status: TeamInvitationStatus.expired),
        ],
      };

      await tester.pumpWidget(
        teamDetailHarness(repository: repository, teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);

      expect(find.text('invite@exemple.fr'), findsOneWidget);
      expect(find.textContaining(strings.shareExpiresAt('')), findsOneWidget);
    });

    testWidgets('invite par adresse', (tester) async {
      useSurface(tester, const Size(900, 1600));
      final FakeTeamRepository repository = FakeTeamRepository();

      await tester.pumpWidget(
        teamDetailHarness(repository: repository, teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);
      await tester.tap(
        find.widgetWithText(LimpidButton, strings.teamsInviteEmail),
      );
      await tester.pumpAndSettle();

      expect(find.text(strings.fieldEmail), findsOneWidget);
      // La boite porte son propre choix de role : l'ecran des membres en
      // porte un aussi, pour chaque membre de l'equipe.
      expect(
        find.descendant(
          of: find.byType(LimpidDialog),
          matching: find.text(strings.teamsRole),
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'invite@exemple.fr');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(LimpidDialog),
          matching: find.widgetWithText(LimpidButton, strings.teamsInvite),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.emailInvitations['team-1'], hasLength(1));
      expect(
        repository.emailInvitations['team-1']!.first.email,
        'invite@exemple.fr',
      );
    });

    testWidgets('montre le lien une seule fois quand le serveur le rend', (
      tester,
    ) async {
      useSurface(tester, const Size(900, 1600));
      final FakeTeamRepository repository = FakeTeamRepository();
      repository.invitationLink =
          'https://api.test/v1/team-invitations/lt.1.s/accept';

      await tester.pumpWidget(
        teamDetailHarness(repository: repository, teamId: 'team-1'),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = teamStrings(tester);
      await tester.tap(
        find.widgetWithText(LimpidButton, strings.teamsInviteEmail),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'invite@exemple.fr');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(LimpidDialog),
          matching: find.widgetWithText(LimpidButton, strings.teamsInvite),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('https://api.test/v1/team-invitations/lt.1.s/accept'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(LimpidButton, strings.shareCopy),
        findsOneWidget,
      );
    });
  });
}
