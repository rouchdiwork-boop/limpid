import 'package:limpid_core/limpid_core.dart';
import 'package:postgres/postgres.dart';

import '../errors/app_exception.dart';
import 'team_database.dart';
import 'team_invitation_record.dart';
import 'team_record.dart';

/// L'implémentation Postgres des équipes.
///
/// Chaque requête est paramétrée : aucune valeur n'atteint le serveur par
/// concaténation. L'invitation est écrite dans une transaction qui verrouille
/// la ligne de l'équipe : deux invitations simultanées ne peuvent pas
/// dépasser la limite de sièges.
final class PostgresTeamDatabase implements TeamDatabase {
  /// Crée une base sur [pool].
  ///
  /// [planLookup] lit la formule du compte ; la composition y injecte la
  /// lecture des formules, la base n'en sait rien.
  PostgresTeamDatabase(this._pool, {PlanLookup? planLookup})
    : _planLookup = planLookup ?? _freePlan;

  final Pool<Object?> _pool;
  final PlanLookup _planLookup;

  static final UlidGenerator _ulid = UlidGenerator();

  static const String _teamColumns =
      'id, name, owner_id, created_at, updated_at';

  static const String _qualifiedTeamColumns =
      't.id, t.name, t.owner_id, t.created_at, t.updated_at';

  static const String _memberColumns = 'team_id, user_id, role, created_at';

  /// Renvoie toujours `null` : le compte est traité comme « Gratuit ».
  static Future<String?> _freePlan(String userId) async => null;

  @override
  PlanLookup get planLookup => _planLookup;

  @override
  Future<List<TeamRecord>> listTeams({required String userId}) async {
    final Result result = await _pool.execute(
      'SELECT $_qualifiedTeamColumns FROM teams t '
      'JOIN team_members m ON m.team_id = t.id AND m.user_id = \$1 '
      'ORDER BY t.created_at ASC, t.id ASC',
      parameters: <Object?>[userId],
    );
    return List<TeamRecord>.unmodifiable(
      result.map(_readTeam).toList(growable: false),
    );
  }

  @override
  Future<TeamMember?> findMember({
    required String teamId,
    required String userId,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_memberColumns FROM team_members '
      'WHERE team_id = \$1 AND user_id = \$2',
      parameters: <Object?>[teamId, userId],
    );
    return result.isEmpty ? null : _readMember(result.first);
  }

  @override
  Future<TeamRecord?> findTeam({required String teamId}) async {
    final Result result = await _pool.execute(
      'SELECT $_teamColumns FROM teams WHERE id = \$1',
      parameters: <Object?>[teamId],
    );
    return result.isEmpty ? null : _readTeam(result.first);
  }

  @override
  Future<List<TeamMember>> listMembers({required String teamId}) async {
    final Result result = await _pool.execute(
      'SELECT $_memberColumns FROM team_members WHERE team_id = \$1 '
      "ORDER BY CASE role WHEN '${TeamRole.owner.name}' THEN 0 ELSE 1 END, "
      'created_at ASC, user_id ASC',
      parameters: <Object?>[teamId],
    );
    return List<TeamMember>.unmodifiable(
      result.map(_readMember).toList(growable: false),
    );
  }

  @override
  Future<TeamRecord> createTeam({
    required String ownerId,
    required String name,
  }) async {
    return _pool.runTx((Session session) async {
      final String id = _ulid.generate().value;
      await session.execute(
        'INSERT INTO teams (id, name, owner_id, created_at, updated_at) '
        'VALUES (\$1, \$2, \$3, now(), now())',
        parameters: <Object?>[id, name, ownerId],
      );
      await session.execute(
        'INSERT INTO team_members (team_id, user_id, role, created_at) '
        'VALUES (\$1, \$2, \$3, now())',
        parameters: <Object?>[id, ownerId, TeamRole.owner.name],
      );
      final Result stored = await session.execute(
        'SELECT $_teamColumns FROM teams WHERE id = \$1',
        parameters: <Object?>[id],
      );
      if (stored.isEmpty) {
        throw StateError('Team $id could not be read back after creation.');
      }
      return _readTeam(stored.first);
    });
  }

  @override
  Future<MemberAddition?> addMember({
    required String teamId,
    required String userId,
    required TeamRole role,
    required String invitedBy,
    required int maxSeats,
  }) async {
    return _pool.runTx((Session session) async {
      final Result locked = await session.execute(
        'SELECT id FROM teams WHERE id = \$1 FOR UPDATE',
        parameters: <Object?>[teamId],
      );
      if (locked.isEmpty) throw const NotFoundException();

      final Result existing = await session.execute(
        'SELECT user_id FROM team_members WHERE team_id = \$1 AND user_id = \$2',
        parameters: <Object?>[teamId, userId],
      );
      if (existing.isNotEmpty) {
        throw const ConflictException(
          message: 'Ce compte fait déjà partie de l\'équipe.',
        );
      }

      final Result seats = await session.execute(
        'SELECT count(*) AS total FROM team_members '
        'WHERE team_id = \$1 AND role <> \$2',
        parameters: <Object?>[teamId, TeamRole.owner.name],
      );
      final int used = seats.isEmpty ? 0 : _readTotal(seats.first);
      if (used >= maxSeats) return null;

      await session.execute(
        'INSERT INTO team_members (team_id, user_id, role, created_at) '
        'VALUES (\$1, \$2, \$3, now())',
        parameters: <Object?>[teamId, userId, role.name],
      );
      final String invitationId = _ulid.generate().value;
      await session.execute(
        'INSERT INTO team_invitations '
        '(id, team_id, user_id, role, invited_by, created_at) '
        'VALUES (\$1, \$2, \$3, \$4, \$5, now())',
        parameters: <Object?>[
          invitationId,
          teamId,
          userId,
          role.name,
          invitedBy,
        ],
      );

      final Result member = await session.execute(
        'SELECT $_memberColumns FROM team_members '
        'WHERE team_id = \$1 AND user_id = \$2',
        parameters: <Object?>[teamId, userId],
      );
      final Result invitation = await session.execute(
        'SELECT id, team_id, user_id, role, invited_by, created_at '
        'FROM team_invitations WHERE id = \$1',
        parameters: <Object?>[invitationId],
      );
      if (member.isEmpty || invitation.isEmpty) {
        throw StateError('The invitation of $userId could not be read back.');
      }
      return MemberAddition(
        member: _readMember(member.first),
        invitation: _readInvitation(invitation.first),
      );
    });
  }

  @override
  Future<TeamMember?> changeMemberRole({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async {
    final Result result = await _pool.execute(
      'UPDATE team_members SET role = \$3 '
      'WHERE team_id = \$1 AND user_id = \$2 '
      'RETURNING $_memberColumns',
      parameters: <Object?>[teamId, userId, role.name],
    );
    return result.isEmpty ? null : _readMember(result.first);
  }

  @override
  Future<bool> removeMember({
    required String teamId,
    required String userId,
  }) async {
    final Result result = await _pool.execute(
      'DELETE FROM team_members WHERE team_id = \$1 AND user_id = \$2',
      parameters: <Object?>[teamId, userId],
    );
    return result.isEmpty ? false : true;
  }

  @override
  Future<bool> deleteTeam({required String teamId}) async {
    final Result result = await _pool.execute(
      'DELETE FROM teams WHERE id = \$1',
      parameters: <Object?>[teamId],
    );
    return result.isEmpty ? false : true;
  }

  @override
  Future<InvitationAcceptanceOutcome> acceptInvitation({
    required String invitationId,
    required String teamId,
    required String userId,
    required TeamRole role,
    required String invitedBy,
    required int maxSeats,
  }) async {
    return _pool.runTx((Session session) async {
      // La ligne de l'équipe est verrouillée : deux acceptations
      // simultanées ne peuvent pas dépasser la limite de sièges.
      final Result locked = await session.execute(
        'SELECT id FROM teams WHERE id = \$1 FOR UPDATE',
        parameters: <Object?>[teamId],
      );
      if (locked.isEmpty) throw const NotFoundException();

      // Le compte ne peut pas entrer deux fois dans l'équipe : l'invitation
      // porte une adresse, elle ne dit pas que le compte est déjà membre.
      final Result existing = await session.execute(
        'SELECT user_id FROM team_members WHERE team_id = \$1 AND user_id = \$2',
        parameters: <Object?>[teamId, userId],
      );
      if (existing.isNotEmpty) {
        throw const ConflictException(
          message: 'Ce compte fait déjà partie de l\'équipe.',
        );
      }

      // Les sièges sont vérifiés au moment de l'acceptation : la formule a
      // pu changer entre l'invitation et la réponse.
      final Result seats = await session.execute(
        'SELECT count(*) AS total FROM team_members '
        'WHERE team_id = \$1 AND role <> \$2',
        parameters: <Object?>[teamId, TeamRole.owner.name],
      );
      final int used = seats.isEmpty ? 0 : _readTotal(seats.first);
      if (used >= maxSeats) return InvitationAcceptanceOutcome.noSeat;

      // L'invitation est consommée : la condition sur l'état et sur
      // l'échéance fait qu'un même jeton ne marche qu'une fois.
      final Result accepted = await session.execute(
        'UPDATE team_invitations '
        'SET status = \$1, accepted_at = now(), accepted_by = \$2, user_id = \$2 '
        'WHERE id = \$3 AND status = \$4 AND expires_at > now()',
        parameters: <Object?>[
          TeamInvitationStatus.accepted.name,
          userId,
          invitationId,
          TeamInvitationStatus.pending.name,
        ],
      );
      if (accepted.isEmpty) return InvitationAcceptanceOutcome.alreadyUsed;

      await session.execute(
        'INSERT INTO team_members (team_id, user_id, role, created_at) '
        'VALUES (\$1, \$2, \$3, now())',
        parameters: <Object?>[teamId, userId, role.name],
      );
      return InvitationAcceptanceOutcome.accepted;
    });
  }

  static TeamRecord _readTeam(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return TeamRecord(
      id: columns['id']! as String,
      name: columns['name']! as String,
      ownerId: columns['owner_id']! as String,
      createdAt: _readDate(columns['created_at']),
      updatedAt: _readDate(columns['updated_at']),
    );
  }

  static TeamMember _readMember(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    final String raw = columns['role']! as String;
    final TeamRole? role = TeamRole.parse(raw);
    if (role == null) {
      throw FormatException('Unknown team role "$raw".');
    }
    return TeamMember(
      teamId: columns['team_id']! as String,
      userId: columns['user_id']! as String,
      role: role,
      createdAt: _readDate(columns['created_at']),
    );
  }

  static TeamInvitation _readInvitation(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    final String raw = columns['role']! as String;
    final TeamRole? role = TeamRole.parse(raw);
    if (role == null) {
      throw FormatException('Unknown team role "$raw".');
    }
    return TeamInvitation(
      id: columns['id']! as String,
      teamId: columns['team_id']! as String,
      userId: columns['user_id']! as String,
      role: role,
      invitedBy: columns['invited_by']! as String,
      createdAt: _readDate(columns['created_at']),
    );
  }

  static int _readTotal(ResultRow row) {
    final Object? value = row.toColumnMap()['total'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
  }
}
