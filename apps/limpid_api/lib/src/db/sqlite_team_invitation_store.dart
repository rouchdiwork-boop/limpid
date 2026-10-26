import 'package:sqlite3/sqlite3.dart';

import 'sqlite_database.dart';
import 'sqlite_values.dart';
import 'team_invitation_record.dart';
import 'team_invitation_store.dart';
import 'team_record.dart';

/// L'implémentation SQLite du port [TeamInvitationStore].
///
/// L'adaptateur est la traduction de celui de Postgres : mêmes requêtes,
/// même ordre de tri et mêmes invariants. Chaque requête est paramétrée :
/// aucune valeur n'atteint le moteur par concaténation.
///
/// Les horodatages sont stockés en microsecondes depuis l'époque Unix, la
/// convention du dialecte SQLite (voir `SqliteValues`).
final class SqliteTeamInvitationStore implements TeamInvitationStore {
  /// Crée un magasin sur la base [database].
  const SqliteTeamInvitationStore(this._database);

  /// La base des invitations.
  final SqliteDatabase _database;

  static const String _columns =
      'id, team_id, user_id, email, role, token_hash, status, invited_by, '
      'created_at, expires_at, accepted_at, accepted_by';

  @override
  Future<TeamInvitationRecord?> findById(String id) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM team_invitations WHERE id = ?',
        <Object?>[id],
      );
      return result.isEmpty ? null : _readInvitation(result.first);
    });
  }

  @override
  Future<List<TeamInvitationRecord>> listByTeam({
    required String teamId,
  }) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM team_invitations '
        'WHERE team_id = ? AND email IS NOT NULL '
        'ORDER BY created_at DESC, id ASC',
        <Object?>[teamId],
      );
      return List<TeamInvitationRecord>.unmodifiable(
        result.map(_readInvitation).toList(growable: false),
      );
    });
  }

  @override
  Future<TeamInvitationRecord?> findPendingByEmail({
    required String teamId,
    required String email,
  }) async {
    final int now = SqliteValues.encodeTimestamp(DateTime.now().toUtc());
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM team_invitations '
        'WHERE team_id = ? AND email = ? AND status = ? AND expires_at > ?',
        <Object?>[teamId, email, TeamInvitationStatus.pending.name, now],
      );
      return result.isEmpty ? null : _readInvitation(result.first);
    });
  }

  @override
  Future<void> insert(TeamInvitationRecord record) async {
    await _database.run(() {
      _database.connection.execute(
        'INSERT INTO team_invitations '
        '($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          record.id,
          record.teamId,
          null,
          record.email,
          record.role.name,
          record.tokenHash,
          record.status.name,
          record.invitedBy,
          SqliteValues.encodeTimestamp(record.createdAt),
          SqliteValues.encodeTimestamp(record.expiresAt),
          record.acceptedAt == null
              ? null
              : SqliteValues.encodeTimestamp(record.acceptedAt!),
          record.acceptedBy,
        ],
      );
    });
  }

  @override
  Future<bool> markAccepted({
    required String id,
    required String userId,
    required DateTime acceptedAt,
  }) async {
    return _database.run(() {
      _database.connection.execute(
        'UPDATE team_invitations '
        'SET status = ?, accepted_at = ?, accepted_by = ?, user_id = ? '
        'WHERE id = ? AND status = ? AND expires_at > ?',
        <Object?>[
          TeamInvitationStatus.accepted.name,
          SqliteValues.encodeTimestamp(acceptedAt),
          userId,
          userId,
          id,
          TeamInvitationStatus.pending.name,
          SqliteValues.encodeTimestamp(acceptedAt),
        ],
      );
      return _database.connection.updatedRows > 0;
    });
  }

  @override
  Future<TeamInvitationRecord?> revoke({
    required String id,
    required String teamId,
  }) async {
    return _database.transaction(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM team_invitations WHERE id = ?',
        <Object?>[id],
      );
      if (result.isEmpty) return null;
      final TeamInvitationRecord existing = _readInvitation(result.first);
      if (existing.teamId != teamId) return null;
      if (existing.status != TeamInvitationStatus.pending) return existing;

      _database.connection.execute(
        'UPDATE team_invitations SET status = ? WHERE id = ?',
        <Object?>[TeamInvitationStatus.revoked.name, id],
      );
      final ResultSet updated = _database.connection.select(
        'SELECT $_columns FROM team_invitations WHERE id = ?',
        <Object?>[id],
      );
      return updated.isEmpty ? existing : _readInvitation(updated.first);
    });
  }

  /// L'invitation d'une ligne de la base.
  static TeamInvitationRecord _readInvitation(Row row) {
    final String rawRole = row['role']! as String;
    final TeamRole? role = TeamRole.parse(rawRole);
    if (role == null) {
      throw FormatException('Unknown team role "$rawRole".');
    }
    final String rawStatus = row['status']! as String;
    final TeamInvitationStatus? status = TeamInvitationStatus.parse(rawStatus);
    if (status == null) {
      throw FormatException('Unknown team invitation status "$rawStatus".');
    }
    final DateTime createdAt = SqliteValues.decodeTimestamp(row['created_at']);
    final Object? rawExpiresAt = row['expires_at'];
    return TeamInvitationRecord(
      id: row['id']! as String,
      teamId: row['team_id']! as String,
      email: (row['email'] as String?) ?? '',
      role: role,
      tokenHash: (row['token_hash'] as String?) ?? '',
      status: status,
      invitedBy: row['invited_by']! as String,
      createdAt: createdAt,
      // Les invitations immédiates — les traces écrites par la base des
      // équipes — n'ont pas d'échéance : elles datent de l'invitation.
      expiresAt: rawExpiresAt == null
          ? createdAt
          : SqliteValues.decodeTimestamp(rawExpiresAt),
      acceptedAt: SqliteValues.decodeNullableTimestamp(row['accepted_at']),
      acceptedBy: row['accepted_by'] as String?,
    );
  }
}
