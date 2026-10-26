import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/team_repository.dart';

/// Les équipes de l'auteur, servies par l'API.
///
/// Les six routes de `/v1/teams` décrivent le cycle de vie d'une équipe :
/// la liste, la création, les membres, l'invitation, le changement de rôle,
/// le retrait et la suppression.
///
/// Le dépôt ne laisse jamais sortir une exception brute : un échec est
/// toujours l'un des types de `domain/errors.dart`.
final class ApiTeamRepository implements TeamRepository {
  /// Crée un dépôt sur le dessus de [client].
  const ApiTeamRepository({required this.client});

  /// Le client de l'API.
  final ApiClient client;

  /// L'instant d'un enregistrement dont le serveur ne publie pas la date.
  ///
  /// L'interface n'affiche pas les dates des membres : la valeur ne sert
  /// qu'à garder le modèle complet, sans inventer un moment faux.
  static final DateTime _unknownMoment = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  @override
  Future<List<Team>> listTeams() async {
    final Object? payload = await client.get('/v1/teams');
    if (payload is! List<dynamic>) {
      throw const ApiMalformedResponseException(
        'The API did not return the list of the teams.',
      );
    }
    final List<Team> teams = <Team>[];
    for (final Object? item in payload) {
      teams.add(_teamOf(_objectOf(item)));
    }
    return List<Team>.unmodifiable(teams);
  }

  @override
  Future<Team> createTeam({required String name}) async {
    final Object? payload = await client.post(
      '/v1/teams',
      body: <String, Object?>{'name': name},
    );
    return _teamOf(_objectOf(payload));
  }

  @override
  Future<List<TeamMember>> listMembers({required String teamId}) async {
    final Object? payload = await client.get(_membersPath(teamId));
    if (payload is! List<dynamic>) {
      throw const ApiMalformedResponseException(
        'The API did not return the list of the members.',
      );
    }
    final List<TeamMember> members = <TeamMember>[];
    for (final Object? item in payload) {
      members.add(_memberOf(_objectOf(item)));
    }
    return List<TeamMember>.unmodifiable(members);
  }

  @override
  Future<TeamInvitation> invite({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async {
    final Object? payload = await client.post(
      _invitationsPath(teamId),
      body: <String, Object?>{'user_id': userId, 'role': role.name},
    );
    return _invitationOf(_objectOf(payload));
  }

  @override
  Future<CreatedTeamInvitation> inviteByEmail({
    required String teamId,
    required String email,
    required TeamRole role,
  }) async {
    final Object? payload = await client.post(
      _invitationsPath(teamId),
      body: <String, Object?>{'email': email, 'role': role.name},
    );
    final Map<String, Object?> data = _objectOf(payload);
    return CreatedTeamInvitation(
      invitation: _emailInvitationOf(data),
      // Le lien ne vient que lorsqu'aucun fournisseur de courriel n'est
      // configuré : quand le courriel part, il n'est plus rendu.
      link: _stringOf(data['invitation_link']),
    );
  }

  @override
  Future<List<TeamEmailInvitation>> listInvitations({
    required String teamId,
  }) async {
    final Object? payload = await client.get(_invitationsPath(teamId));
    if (payload is! List<dynamic>) {
      throw const ApiMalformedResponseException(
        'The API did not return the list of the invitations.',
      );
    }
    final List<TeamEmailInvitation> invitations = <TeamEmailInvitation>[];
    for (final Object? item in payload) {
      invitations.add(_emailInvitationOf(_objectOf(item)));
    }
    return List<TeamEmailInvitation>.unmodifiable(invitations);
  }

  @override
  Future<TeamEmailInvitation> revokeInvitation({
    required String teamId,
    required String invitationId,
  }) async {
    final Object? payload = await client.delete(
      '${_invitationsPath(teamId)}/${Uri.encodeComponent(invitationId)}',
    );
    return _emailInvitationOf(_objectOf(payload));
  }

  @override
  Future<TeamEmailInvitation> acceptInvitation({required String token}) async {
    final Object? payload = await client.post(
      '/v1/team-invitations/${Uri.encodeComponent(token)}/accept',
    );
    return _emailInvitationOf(_objectOf(payload));
  }

  @override
  Future<TeamMember> changeRole({
    required String teamId,
    required String userId,
    required TeamRole role,
  }) async {
    final Object? payload = await client.patch(
      _memberPath(teamId, userId),
      body: <String, Object?>{'role': role.name},
    );
    return _memberOf(_objectOf(payload));
  }

  @override
  Future<void> removeMember({
    required String teamId,
    required String userId,
  }) async {
    await client.delete(_memberPath(teamId, userId));
  }

  @override
  Future<void> deleteTeam({required String teamId}) async {
    await client.delete('/v1/teams/${Uri.encodeComponent(teamId)}');
  }

  /// Le chemin de la liste des membres de l'équipe [teamId].
  static String _membersPath(String teamId) =>
      '/v1/teams/${Uri.encodeComponent(teamId)}/members';

  /// Le chemin des invitations de l'équipe [teamId].
  static String _invitationsPath(String teamId) =>
      '/v1/teams/${Uri.encodeComponent(teamId)}/invitations';

  /// Le chemin du membre [userId] de l'équipe [teamId].
  static String _memberPath(String teamId, String userId) =>
      '${_membersPath(teamId)}/${Uri.encodeComponent(userId)}';

  /// L'équipe d'une réponse du serveur.
  static Team _teamOf(Map<String, Object?> data) {
    return Team(
      id: _stringOf(data['id']) ?? '',
      name: _stringOf(data['name']) ?? '',
      ownerId: _stringOf(data['owner_id']) ?? '',
      createdAt: _momentOf(data['created_at']),
      updatedAt: _momentOf(data['updated_at']),
    );
  }

  /// Le membre d'une réponse du serveur.
  static TeamMember _memberOf(Map<String, Object?> data) {
    return TeamMember(
      teamId: _stringOf(data['team_id']) ?? '',
      userId: _stringOf(data['user_id']) ?? '',
      role: _roleOf(data['role']),
      createdAt: _momentOf(data['created_at']),
    );
  }

  /// L'invitation d'une réponse du serveur.
  static TeamInvitation _invitationOf(Map<String, Object?> data) {
    return TeamInvitation(
      id: _stringOf(data['id']) ?? '',
      teamId: _stringOf(data['team_id']) ?? '',
      userId: _stringOf(data['user_id']) ?? '',
      role: _roleOf(data['role']),
      invitedBy: _stringOf(data['invited_by']) ?? '',
      createdAt: _momentOf(data['created_at']),
    );
  }

  /// Le rôle d'une réponse du serveur.
  ///
  /// Un rôle que l'interface ne connaît pas est lu comme
  /// [TeamRole.reader] : le rôle le plus prudent.
  static TeamRole _roleOf(Object? value) {
    return TeamRole.parse(_stringOf(value) ?? '') ?? TeamRole.reader;
  }

  /// L'invitation par adresse d'une réponse du serveur.
  ///
  /// Un état que l'interface ne connaît pas est lu comme
  /// [TeamInvitationStatus.expired] : l'état le moins actif, celui qui ne
  /// laisse croire à personne que l'invitation attend encore une réponse.
  static TeamEmailInvitation _emailInvitationOf(Map<String, Object?> data) {
    return TeamEmailInvitation(
      id: _stringOf(data['id']) ?? '',
      teamId: _stringOf(data['team_id']) ?? '',
      email: _stringOf(data['email']) ?? '',
      role: _roleOf(data['role']),
      status:
          TeamInvitationStatus.parse(_stringOf(data['status']) ?? '') ??
          TeamInvitationStatus.expired,
      invitedBy: _stringOf(data['invited_by']) ?? '',
      createdAt: _momentOf(data['created_at']),
      expiresAt: _momentOf(data['expires_at']),
      acceptedAt: _optionalMomentOf(data['accepted_at']),
      acceptedBy: _stringOf(data['accepted_by']),
    );
  }

  /// Le corps de la réponse, quand il est un objet.
  static Map<String, Object?> _objectOf(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const ApiMalformedResponseException(
      'The API did not return the expected payload.',
    );
  }

  static String? _stringOf(Object? value) {
    if (value is String) return value;
    return null;
  }

  static DateTime _momentOf(Object? value) {
    if (value is! String) return _unknownMoment;
    return DateTime.tryParse(value)?.toUtc() ?? _unknownMoment;
  }

  /// L'instant d'un enregistrement dont le serveur ne publie pas la date.
  static DateTime? _optionalMomentOf(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
