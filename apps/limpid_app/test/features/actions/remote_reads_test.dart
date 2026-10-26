import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/auth/two_factor_proof_holder.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/team_repository.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';
import 'package:limpid_app/src/features/teams/teams_providers.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../../security/fakes.dart' as security;
import 'fakes.dart';

/// Les lectures distantes passent par la fenetre du second facteur.
///
/// Une lecture vit dans un `FutureProvider`, qui n'a pas de
/// `BuildContext` : c'est la cle de navigation de la composition racine qui
/// ouvre la fenetre. Sans elle, un compte qui a active le second facteur
/// ne pourrait plus **lire** ses equipes, ses rappels ou ses quotas.
void main() {
  setUp(TwoFactorProofHolder.reset);
  tearDown(TwoFactorProofHolder.reset);

  testWidgets('le refus ouvre la fenetre et la lecture est repetee', (
    tester,
  ) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>(
      debugLabel: 'test',
    );
    final RefusingTeamsReader repository = RefusingTeamsReader();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          teamRepositoryProvider.overrideWithValue(repository),
          twoFactorRepositoryProvider.overrideWithValue(
            security.FakeTwoFactorRepository(state: security.fakeTwoFactorOn),
          ),
          navigatorKeyProvider.overrideWithValue(navigatorKey),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: LimpidTheme.of(LimpidThemeVariant.paper),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const _TeamsSurface(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final AppLocalizations strings = AppLocalizations.of(
      tester.element(find.byType(_TeamsSurface)),
    );

    // La premiere lecture est refusee, et la fenetre s'ouvre.
    expect(repository.calls, 1);
    expect(find.text(strings.twoFactorProofMissing), findsOneWidget);
    expect(repository.proofs, <String?>[null]);

    await _giveTheCode(tester, strings);

    // La lecture est repetee, et elle porte la preuve.
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(repository.proofs.last, isNotNull);
    expect(find.text(strings.twoFactorProofMissing), findsNothing);
  });

  testWidgets(
    'une lecture refusee pour une autre raison n ouvre pas la fenetre',
    (tester) async {
      final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>(
        debugLabel: 'test',
      );
      final RefusingTeamsReader repository = RefusingTeamsReader()
        ..refusal = const ApiNotFoundException('Cette equipe n existe pas.');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            teamRepositoryProvider.overrideWithValue(repository),
            twoFactorRepositoryProvider.overrideWithValue(
              security.FakeTwoFactorRepository(state: security.fakeTwoFactorOn),
            ),
            navigatorKeyProvider.overrideWithValue(navigatorKey),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: LimpidTheme.of(LimpidThemeVariant.paper),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const _TeamsSurface(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = AppLocalizations.of(
        tester.element(find.byType(_TeamsSurface)),
      );

      // Un `404` n'a rien a voir avec le second facteur : aucune fenetre.
      expect(repository.calls, 1);
      expect(find.text(strings.twoFactorProofMissing), findsNothing);
    },
  );
}

/// Un depot d'equipes qui refuse la premiere lecture.
///
/// Le faux de `fakes.dart` refuse la premiere **ecriture** ; celui-ci
/// refuse la premiere lecture, comme le fait le serveur quand la preuve
/// du second facteur a expire.
final class RefusingTeamsReader
    with RefusesTheFirstCall
    implements TeamRepository {
  @override
  Future<List<Team>> listTeams() async {
    refuseIfFirst();
    return const <Team>[];
  }

  @override
  Future<Team> createTeam({required String name}) async =>
      throw UnimplementedError();

  @override
  Future<Team> deleteTeam({required String teamId}) async =>
      throw UnimplementedError();

  @override
  Future<TeamInvitation> invite({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async => throw UnimplementedError();

  @override
  Future<CreatedTeamInvitation> inviteByEmail({
    required String teamId,
    required String email,
    required TeamRole role,
  }) async => throw UnimplementedError();

  @override
  Future<List<TeamEmailInvitation>> listInvitations({
    required String teamId,
  }) async => throw UnimplementedError();

  @override
  Future<TeamEmailInvitation> revokeInvitation({
    required String teamId,
    required String invitationId,
  }) async => throw UnimplementedError();

  @override
  Future<TeamEmailInvitation> acceptInvitation({required String token}) async =>
      throw UnimplementedError();

  @override
  Future<List<TeamMember>> listMembers({required String teamId}) async =>
      const <TeamMember>[];

  @override
  Future<TeamMember> changeRole({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async => throw UnimplementedError();

  @override
  Future<void> removeMember({
    required String teamId,
    required String userId,
  }) async => throw UnimplementedError();
}

/// L'ecran qui lit les equipes du compte.
class _TeamsSurface extends ConsumerWidget {
  /// Cree l'ecran.
  const _TeamsSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Team>> teams = ref.watch(teamsProvider);
    return Scaffold(
      body: Center(
        child: Text(switch (teams) {
          AsyncData<List<Team>>(value: final List<Team> list) =>
            '${list.length} equipes',
          AsyncError<List<Team>>() => 'erreur',
          _ => 'chargement',
        }),
      ),
    );
  }
}

/// Donne le code a la fenetre du second facteur.
Future<void> _giveTheCode(WidgetTester tester, AppLocalizations strings) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(LimpidDialog),
      matching: find.byType(LimpidTextField),
    ),
    '123456',
  );
  await tester.tap(find.text(strings.twoFactorVerify));
  for (int frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
