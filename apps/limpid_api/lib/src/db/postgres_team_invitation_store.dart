import 'package:postgres/postgres.dart';

import 'team_invitation_record.dart';
import 'team_invitation_store.dart';
import 'team_record.dart';

/// L'implémentation Postgres du port [TeamInvitationStore].
///
/// L'adaptateur est la traduction de celui de SQLite : mêmes requêtes,
/// même ordre de tri et mêmes invariants. Chaque requête est paramétrée :
/// aucune valeur n'atteint le serveur par concaténation.
final class PostgresTeamInvitationStore implements TeamInvitationStore {
  /// Crée un magasin sur [pool].
  const PostgresTeamInvitationStore(this._pool);

  /// Le pool de connexions.
  final Pool<Object?> _pool;

  static const String _columns =
      'id, team_id, user_id, email, role, token_hash, status, invited_by, '
      'created_at, expires_at, accepted_at, accepted_by';

  @override
  Future<TeamInvitationRecord?> findById(String id) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM team_invitations WHERE id = \$1',
      parameters: <Object?>[id],
    );
    return result.isEmpty ? null : _readInvitation(result.first);
  }

  @override
  Future<List<TeamInvitationRecord>> listByTeam({
    required String teamId,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM team_invitations '
      'WHERE team_id = \$1 AND email IS NOT NULL '
      'ORDER BY created_at DESC, id ASC',
      parameters: <Object?>[teamId],
    );
    return List<TeamInvitationRecord>.unmodifiable(
      result.map(_readInvitation).toList(growable: false),
    );
  }

  @override
  Future<TeamInvitationRecord?> findPendingByEmail({
    required String teamId,
    required String email,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM team_invitations '
      'WHERE team_id = \$1 AND email = \$2 AND status = \$3 '
      'AND expires_at > now()',
      parameters: <Object?>[teamId, email, TeamInvitationStatus.pending.name],
    );
    return result.isEmpty ? null : _readInvitation(result.first);
  }

  @override
  Future<void> insert(TeamInvitationRecord record) async {
    await _pool.execute(
      'INSERT INTO team_invitations ($_columns) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12)',
      parameters: <Object?>[
        record.id,
        record.teamId,
        null,
        record.email,
        record.role.name,
        record.tokenHash,
        record.status.name,
        record.invitedBy,
        record.createdAt,
        record.expiresAt,
        record.acceptedAt,
        record.acceptedBy,
      ],
    );
  }

  @override
  Future<bool> markAccepted({
    required String id,
    required String userId,
    required DateTime acceptedAt,
  }) async {
    final Result result = await _pool.execute(
      'UPDATE team_invitations '
      'SET status = \$1, accepted_at = \$2, accepted_by = \$3, user_id = \$4 '
      'WHERE id = \$5 AND status = \$6 AND expires_at > \$2',
      parameters: <Object?>[
        TeamInvitationStatus.accepted.name,
        acceptedAt,
        userId,
        userId,
        id,
        TeamInvitationStatus.pending.name,
      ],
    );
    return result.isNotEmpty;
  }

  @override
  Future<TeamInvitationRecord?> revoke({
    required String id,
    required String teamId,
  }) async {
    return _pool.runTx((Session session) async {
      final Result found = await session.execute(
        'SELECT $_columns FROM team_invitations WHERE id = \$1',
        parameters: <Object?>[id],
      );
      if (found.isEmpty) return null;
      final TeamInvitationRecord existing = _readInvitation(found.first);
      if (existing.teamId != teamId) return null;
      if (existing.status != TeamInvitationStatus.pending) return existing;

      final Result updated = await session.execute(
        'UPDATE team_invitations SET status = \$1 WHERE id = \$2 '
        'RETURNING $_columns',
        parameters: <Object?>[TeamInvitationStatus.revoked.name, id],
      );
      if (updated.isEmpty) return existing;
      return _readInvitation(updated.first);
    });
  }

  /// L'invitation d'une ligne de la base.
  static TeamInvitationRecord _readInvitation(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    final String rawRole = columns['role']! as String;
    final TeamRole? role = TeamRole.parse(rawRole);
    if (role == null) {
      throw FormatException('Unknown team role "$rawRole".');
    }
    final String rawStatus = columns['status']! as String;
    final TeamInvitationStatus? status = TeamInvitationStatus.parse(rawStatus);
    if (status == null) {
      throw FormatException('Unknown team invitation status "$rawStatus".');
    }
    final DateTime createdAt = _readDate(columns['created_at']);
    final Object? rawExpiresAt = columns['expires_at'];
    return TeamInvitationRecord(
      id: columns['id']! as String,
      teamId: columns['team_id']! as String,
      email: (columns['email'] as String?) ?? '',
      role: role,
      tokenHash: (columns['token_hash'] as String?) ?? '',
      status: status,
      invitedBy: columns['invited_by']! as String,
      createdAt: createdAt,
      // Les invitations immédiates — les traces écrites par la base des
      // équipes — n'ont pas d'échéance : elles datent de l'invitation.
      expiresAt: rawExpiresAt == null ? createdAt : _readDate(rawExpiresAt),
      acceptedAt: _readOptionalDate(columns['accepted_at']),
      acceptedBy: columns['accepted_by'] as String?,
    );
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
  }

  static DateTime? _readOptionalDate(Object? value) {
    if (value == null) return null;
    return _readDate(value);
  }
}
