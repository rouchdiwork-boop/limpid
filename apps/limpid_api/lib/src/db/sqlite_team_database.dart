import 'package:limpid_core/limpid_core.dart';
import 'package:sqlite3/sqlite3.dart';

import '../errors/app_exception.dart';
import 'sqlite_database.dart';
import 'sqlite_values.dart';
import 'team_database.dart';
import 'team_record.dart';

/// L'implémentation SQLite des équipes.
///
/// L'adaptateur est la traduction de celui de Postgres : mêmes requêtes,
/// même ordre de tri et mêmes invariants. Chaque requête est paramétrée :
/// aucune valeur n'atteint le moteur par concaténation.
///
/// Les horodatages sont stockés en microsecondes depuis l'époque Unix, la
/// convention du dialecte SQLite (voir `SqliteValues`).
final class SqliteTeamDatabase implements TeamDatabase {
  /// Crée une base sur [database].
  ///
  /// [planLookup] lit la formule du compte ; la composition y injecte la
  /// lecture des formules, la base n'en sait rien.
  SqliteTeamDatabase(this._database, {PlanLookup? planLookup})
    : _planLookup = planLookup ?? _freePlan;

  final SqliteDatabase _database;
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
  Future<List<TeamRecord>> listTeams({required String userId}) {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_qualifiedTeamColumns FROM teams t '
        'JOIN team_members m ON m.team_id = t.id AND m.user_id = ? '
        'ORDER BY t.created_at ASC, t.id ASC',
        <Object?>[userId],
      );
      return List<TeamRecord>.unmodifiable(
        result.map(_readTeam).toList(growable: false),
      );
    });
  }

  @override
  Future<TeamMember?> findMember({
    required String teamId,
    required String userId,
  }) {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_memberColumns FROM team_members '
        'WHERE team_id = ? AND user_id = ?',
        <Object?>[teamId, userId],
      );
      return result.isEmpty ? null : _readMember(result.first);
    });
  }

  @override
  Future<List<TeamMember>> listMembers({required String teamId}) {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_memberColumns FROM team_members WHERE team_id = ? '
        "ORDER BY CASE role WHEN '${TeamRole.owner.name}' THEN 0 ELSE 1 END, "
        'created_at ASC, user_id ASC',
        <Object?>[teamId],
      );
      return List<TeamMember>.unmodifiable(
        result.map(_readMember).toList(growable: false),
      );
    });
  }

  @override
  Future<TeamRecord> createTeam({
    required String ownerId,
    required String name,
  }) {
    return _database.transaction(() {
      final String id = _ulid.generate().value;
      final int timestamp = SqliteValues.encodeTimestamp(
        DateTime.now().toUtc(),
      );

      _database.connection.execute(
        'INSERT INTO teams (id, name, owner_id, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?)',
        <Object?>[id, name, ownerId, timestamp, timestamp],
      );
      _database.connection.execute(
        'INSERT INTO team_members (team_id, user_id, role, created_at) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[id, ownerId, TeamRole.owner.name, timestamp],
      );

      final ResultSet stored = _database.connection.select(
        'SELECT $_teamColumns FROM teams WHERE id = ?',
        <Object?>[id],
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
  }) {
    return _database.transaction(() {
      final ResultSet team = _database.connection.select(
        'SELECT id FROM teams WHERE id = ?',
        <Object?>[teamId],
      );
      if (team.isEmpty) throw const NotFoundException();

      final ResultSet existing = _database.connection.select(
        'SELECT user_id FROM team_members WHERE team_id = ? AND user_id = ?',
        <Object?>[teamId, userId],
      );
      if (existing.isNotEmpty) {
        throw const ConflictException(
          message: 'Ce compte fait déjà partie de l\'équipe.',
        );
      }

      final ResultSet seats = _database.connection.select(
        'SELECT count(*) AS total FROM team_members '
        'WHERE team_id = ? AND role <> ?',
        <Object?>[teamId, TeamRole.owner.name],
      );
      final int used = seats.isEmpty ? 0 : _readTotal(seats.first);
      if (used >= maxSeats) return null;

      final int timestamp = SqliteValues.encodeTimestamp(
        DateTime.now().toUtc(),
      );
      _database.connection.execute(
        'INSERT INTO team_members (team_id, user_id, role, created_at) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[teamId, userId, role.name, timestamp],
      );
      final String invitationId = _ulid.generate().value;
      _database.connection.execute(
        'INSERT INTO team_invitations '
        '(id, team_id, user_id, role, invited_by, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        <Object?>[
          invitationId,
          teamId,
          userId,
          role.name,
          invitedBy,
          timestamp,
        ],
      );

      return MemberAddition(
        member: TeamMember(
          teamId: teamId,
          userId: userId,
          role: role,
          createdAt: SqliteValues.decodeTimestamp(timestamp),
        ),
        invitation: TeamInvitation(
          id: invitationId,
          teamId: teamId,
          userId: userId,
          role: role,
          invitedBy: invitedBy,
          createdAt: SqliteValues.decodeTimestamp(timestamp),
        ),
      );
    });
  }

  @override
  Future<TeamMember?> changeMemberRole({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_memberColumns FROM team_members '
        'WHERE team_id = ? AND user_id = ?',
        <Object?>[teamId, userId],
      );
      if (result.isEmpty) return null;

      _database.connection.execute(
        'UPDATE team_members SET role = ? WHERE team_id = ? AND user_id = ?',
        <Object?>[role.name, teamId, userId],
      );
      final ResultSet updated = _database.connection.select(
        'SELECT $_memberColumns FROM team_members '
        'WHERE team_id = ? AND user_id = ?',
        <Object?>[teamId, userId],
      );
      return updated.isEmpty ? null : _readMember(updated.first);
    });
  }

  @override
  Future<bool> removeMember({required String teamId, required String userId}) {
    return _database.run(() {
      _database.connection.execute(
        'DELETE FROM team_members WHERE team_id = ? AND user_id = ?',
        <Object?>[teamId, userId],
      );
      return _database.connection.updatedRows > 0;
    });
  }

  @override
  Future<bool> deleteTeam({required String teamId}) {
    return _database.run(() {
      _database.connection.execute('DELETE FROM teams WHERE id = ?', <Object?>[
        teamId,
      ]);
      return _database.connection.updatedRows > 0;
    });
  }

  static TeamRecord _readTeam(Row row) {
    return TeamRecord(
      id: row['id']! as String,
      name: row['name']! as String,
      ownerId: row['owner_id']! as String,
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
      updatedAt: SqliteValues.decodeTimestamp(row['updated_at']),
    );
  }

  static TeamMember _readMember(Row row) {
    final String raw = row['role']! as String;
    final TeamRole? role = TeamRole.parse(raw);
    if (role == null) {
      throw FormatException('Unknown team role "$raw".');
    }
    return TeamMember(
      teamId: row['team_id']! as String,
      userId: row['user_id']! as String,
      role: role,
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
    );
  }

  static int _readTotal(Row row) {
    final Object? value = row['total'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
