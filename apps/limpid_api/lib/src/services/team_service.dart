import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:limpid_core/limpid_core.dart';

import '../db/team_database.dart';
import '../db/team_invitation_record.dart';
import '../db/team_invitation_store.dart';
import '../db/team_record.dart';
import '../errors/app_exception.dart';
import 'mailer.dart';
import 'random_secret.dart';
import 'webhook_dispatcher.dart';
import 'webhook_service.dart';

/// Le préfixe d'un jeton d'invitation d'équipe.
///
/// Il permet de reconnaître un jeton d'invitation dans un journal ou une
/// configuration, sans avoir à le déchiffrer.
const String teamInvitationTokenPrefix = 'lt';

/// Le séparateur entre le préfixe, l'identifiant et le secret.
const String teamInvitationTokenSeparator = '.';

/// La durée de vie par défaut d'une invitation, en heures.
///
/// Sept jours suffisent à faire répondre une invitation, sans laisser un
/// lien dormant dans la nature.
const int defaultTeamInvitationLifetimeHours = 168;

/// La durée de vie minimale d'une invitation, en heures.
const int minTeamInvitationLifetimeHours = 1;

/// La durée de vie maximale d'une invitation, en heures.
///
/// Trente jours est la borne de la conservation des données d'un compte
/// (D-19) : une invitation ne vit pas plus longtemps que les données
/// qu'elle ouvre.
const int maxTeamInvitationLifetimeHours = 720;

/// Le nombre maximal de caractères d'une adresse électronique.
const int maxInvitationEmailLength = 254;

/// L'invitation créée et son jeton.
///
/// Le jeton n'existe que dans ce résultat : la base n'en garde que
/// l'empreinte, et le serveur ne rend plus jamais le jeton.
final class CreatedTeamInvitation {
  /// Crée un résultat.
  const CreatedTeamInvitation({
    required this.record,
    required this.token,
    required this.link,
  });

  /// L'invitation telle que la base la stocke.
  final TeamInvitationRecord record;

  /// Le jeton en clair, à montrer une seule fois.
  final String token;

  /// Le lien d'acceptation.
  ///
  /// Le lien porte le jeton : il n'est rendu que lorsqu'aucun fournisseur
  /// de courriel n'est configuré.
  final String link;
}

/// Le service des équipes.
///
/// Le service porte les règles de D-16 : seul le propriétaire invite, change
/// les rôles et supprime l'équipe ; un appelant qui n'est pas membre
/// n'apprend jamais que l'équipe existe, la réponse est un 404 et jamais un
/// 403.
///
/// Il porte deux chemins d'invitation qui cohabitent :
///
/// - l'invitation d'un **compte existant**, qui ajoute le membre sur-le-
///   champ ;
/// - l'invitation par **adresse électronique**, qui attend une réponse :
///   le membre n'est ajouté qu'à l'acceptation, et l'invitation expire.
final class TeamService {
  /// Crée un service sur la base [database].
  ///
  /// [dispatcher] porte les webhooks sortants du compte. Il est facultatif :
  /// un service qui n'a pas de dispatcher n'émet rien, il n'échoue pas non
  /// plus.
  ///
  /// [invitations] porte les invitations en attente : sans lui, le chemin
  /// par courriel est indisponible et le service le dit. [mailer] porte le
  /// message : sans lui, l'invitation est créée mais le lien reste à copier.
  /// [invitationBaseUrl] est l'adresse publique du service : elle sert à
  /// construire le lien d'acceptation.
  ///
  /// [generator] et [clock] sont injectés par la suite de tests : elle fait
  /// passer le temps sans attendre, et elle forge des identifiants
  /// prévisibles.
  TeamService(
    this._database, {
    this.dispatcher,
    this.invitations,
    this.mailer,
    this.invitationBaseUrl = defaultPublicBaseUrl,
    UlidGenerator? generator,
    DateTime Function()? clock,
  }) : _generator = generator ?? UlidGenerator(),
       _clock = clock ?? DateTime.now;

  final TeamDatabase _database;

  /// Le dispatcher des webhooks sortants, `null` quand le service n'en a pas.
  ///
  /// Le service est l'émetteur de l'invitation d'équipe.
  final WebhookDispatcher? dispatcher;

  /// Le magasin des invitations en attente, `null` quand il n'est pas câblé.
  final TeamInvitationStore? invitations;

  /// Le port du courriel, `null` quand il n'est pas câblé.
  final Mailer? mailer;

  /// L'adresse publique du service, pour le lien d'acceptation.
  final String invitationBaseUrl;

  /// Un fournisseur de courriel est-il configuré.
  ///
  /// Quand il ne l'est pas, le lien d'invitation est rendu à l'auteur : il
  /// le copie et le transmet. Quand il l'est, le lien part par courriel et
  /// n'est plus rendu.
  bool get isMailConfigured => mailer?.isConfigured ?? false;

  final UlidGenerator _generator;
  final DateTime Function() _clock;

  /// La formule « Gratuit », appliquée quand la formule est inconnue.
  static const SubscriptionPlan _freePlan = SubscriptionPlan.free;

  /// Les caractères accentués des libellés de formule.
  static const Map<String, String> _accents = <String, String>{
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ÿ': 'y',
  };

  /// Liste les équipes dont [userId] est membre.
  Future<List<TeamRecord>> listTeams(String userId) {
    return _database.listTeams(userId: userId);
  }

  /// Crée une équipe dont [ownerId] est le propriétaire.
  Future<TeamRecord> createTeam({
    required String ownerId,
    required String name,
  }) {
    if (name.trim().isEmpty) {
      throw const ValidationException(
        field: 'name',
        message: 'Le nom de l\'équipe ne peut pas être vide.',
      );
    }
    return _database.createTeam(ownerId: ownerId, name: name);
  }

  /// Liste les membres de l'équipe [teamId] et le rôle de chacun.
  ///
  /// Seuls les membres voient la liste : un appelant extérieur reçoit un 404,
  /// exactement comme pour une équipe qui n'existe pas.
  Future<List<TeamMember>> listMembers({
    required String teamId,
    required String callerId,
  }) async {
    await _requireMember(teamId: teamId, callerId: callerId);
    return _database.listMembers(teamId: teamId);
  }

  /// Invite [userId] dans l'équipe [teamId] avec le rôle [role].
  ///
  /// Seul le propriétaire invite. Le propriétaire n'occupe pas de siège : les
  /// sièges sont les membres invités, et l'équipe n'en accueille pas plus
  /// que la formule du compte n'en accorde. Au-delà, l'invitation est
  /// refusée par une erreur qui nomme la limite atteinte.
  ///
  /// Ce chemin invite un **compte existant** : le membre entre dans l'équipe
  /// sur-le-champ. Le chemin par courriel — [inviteByEmail] — invite une
  /// adresse et attend une réponse.
  Future<TeamInvitation> invite({
    required String teamId,
    required String callerId,
    required String userId,
    required TeamRole role,
  }) async {
    await _requireOwner(
      teamId: teamId,
      callerId: callerId,
      action: 'inviter des membres',
    );
    _requireAssignableRole(role);

    final TeamMember? existing = await _database.findMember(
      teamId: teamId,
      userId: userId,
    );
    if (existing != null) {
      throw const ConflictException(
        message: 'Ce compte fait déjà partie de l\'équipe.',
      );
    }

    final SubscriptionPlan plan = await _planOf(callerId);
    final int maxSeats = PlanDefinition.of(plan).quota.maxSeats;
    final MemberAddition? addition = await _database.addMember(
      teamId: teamId,
      userId: userId,
      role: role,
      invitedBy: callerId,
      maxSeats: maxSeats,
    );
    if (addition == null) {
      throw _seatLimitExceeded(plan, maxSeats);
    }
    _announceInvitation(callerId: callerId, teamId: teamId, role: role);
    return addition.invitation;
  }

  /// Invite l'adresse [email] dans l'équipe [teamId] avec le rôle [role].
  ///
  /// L'invitation **attend** : elle est créée en attente, elle porte un
  /// jeton et une date d'expiration, et le membre n'entre dans l'équipe
  /// qu'à l'acceptation.
  ///
  /// Les sièges sont vérifiés ici — le propriétaire ne propose pas une place
  /// qui n'existe pas — et ils le seront encore à l'acceptation, car la
  /// formule a pu changer entre les deux.
  ///
  /// Le jeton est rendu une seule fois : la base n'en garde que l'empreinte.
  Future<CreatedTeamInvitation> inviteByEmail({
    required String teamId,
    required String callerId,
    required String email,
    required TeamRole role,
    int? lifetimeHours,
  }) async {
    await _requireOwner(
      teamId: teamId,
      callerId: callerId,
      action: 'inviter des membres',
    );
    _requireAssignableRole(role);
    final String address = _readEmail(email);
    final int hours = _readInvitationLifetimeHours(lifetimeHours);
    final TeamInvitationStore store = _requireInvitationStore();

    final TeamRecord? team = await _database.findTeam(teamId: teamId);
    if (team == null) throw const NotFoundException();

    await _requireFreeSeat(teamId: teamId, callerId: callerId);

    final TeamInvitationRecord? duplicate = await store.findPendingByEmail(
      teamId: teamId,
      email: address,
    );
    if (duplicate != null) {
      throw const ConflictException(
        message: 'Une invitation est déjà en attente pour cette adresse.',
      );
    }

    final String id = _generator.generate().value;
    final String token = _presentInvitationToken(id);
    final DateTime now = _now();
    final TeamInvitationRecord record = TeamInvitationRecord(
      id: id,
      teamId: teamId,
      email: address,
      role: role,
      tokenHash: hashTeamInvitationToken(token),
      status: TeamInvitationStatus.pending,
      invitedBy: callerId,
      createdAt: now,
      expiresAt: now.add(Duration(hours: hours)),
    );
    await store.insert(record);

    final String link = TeamInvitationLink.build(
      baseUrl: invitationBaseUrl,
      token: token,
    ).value;
    await mailer?.sendTeamInvitation(
      TeamInvitationMail(
        recipient: address,
        teamName: team.name,
        role: role,
        link: link,
        expiresAt: record.expiresAt,
      ),
    );

    return CreatedTeamInvitation(record: record, token: token, link: link);
  }

  /// Les invitations en attente de l'équipe [teamId].
  ///
  /// Seul le propriétaire les voit : une invitation porte une adresse, et
  /// une adresse n'appartient pas à toute l'équipe.
  Future<List<TeamInvitationRecord>> listInvitations({
    required String teamId,
    required String callerId,
  }) async {
    await _requireOwner(
      teamId: teamId,
      callerId: callerId,
      action: 'consulter les invitations',
    );
    return _requireInvitationStore().listByTeam(teamId: teamId);
  }

  /// Révoque l'invitation [invitationId] de l'équipe [teamId].
  ///
  /// La révocation est irréversible : une invitation révoquée ne s'accepte
  /// plus. Elle est idempotente : révoquer une invitation déjà révoquée
  /// rend la même invitation.
  Future<TeamInvitationRecord> revokeInvitation({
    required String teamId,
    required String callerId,
    required String invitationId,
  }) async {
    await _requireOwner(
      teamId: teamId,
      callerId: callerId,
      action: 'révoquer les invitations',
    );
    final TeamInvitationRecord? revoked = await _requireInvitationStore()
        .revoke(id: invitationId, teamId: teamId);
    if (revoked == null) throw const NotFoundException();
    if (revoked.status == TeamInvitationStatus.accepted) {
      throw const ConflictException(
        message:
            'Cette invitation a déjà été acceptée : le compte fait partie '
            'de l\'équipe.',
      );
    }
    return revoked;
  }

  /// Accepte l'invitation que porte le jeton [token].
  ///
  /// Le compte [callerId] doit porter l'adresse [callerEmail] : une
  /// invitation n'est jamais acceptée par quelqu'un d'autre. Un jeton
  /// inconnu, expiré, révoqué ou déjà accepté répond la même chose : un
  /// 404, jamais un « cette invitation existe, mais pour quelqu'un
  /// d'autre ».
  ///
  /// L'acceptation **consomme** l'invitation : le même jeton ne marche
  /// qu'une fois, et il faut une nouvelle invitation pour inviter de nouveau.
  Future<TeamInvitationRecord> acceptInvitation({
    required String token,
    required String callerId,
    required String callerEmail,
  }) async {
    final TeamInvitationRecord? invitation = await _resolveInvitation(token);
    if (invitation == null) throw const NotFoundException();

    final String address = _normalizeEmail(callerEmail);
    if (address.isEmpty || address != invitation.email) {
      throw const NotFoundException();
    }

    // Les sièges sont vérifiés une seconde fois : la formule a pu changer
    // entre l'invitation et la réponse.
    final SubscriptionPlan plan = await _planOf(invitation.invitedBy);
    final int maxSeats = PlanDefinition.of(plan).quota.maxSeats;
    final InvitationAcceptanceOutcome outcome = await _database
        .acceptInvitation(
          invitationId: invitation.id,
          teamId: invitation.teamId,
          userId: callerId,
          role: invitation.role,
          invitedBy: invitation.invitedBy,
          maxSeats: maxSeats,
        );

    return switch (outcome) {
      InvitationAcceptanceOutcome.accepted => invitation.copyWith(
        status: TeamInvitationStatus.accepted,
        acceptedAt: _now(),
        acceptedBy: callerId,
      ),
      InvitationAcceptanceOutcome.noSeat => throw _seatLimitExceeded(
        plan,
        maxSeats,
      ),
      InvitationAcceptanceOutcome.alreadyUsed =>
        throw const NotFoundException(),
    };
  }

  /// Annonce l'invitation d'un membre dans l'équipe [teamId].
  ///
  /// L'événement part vers les points de rappel du propriétaire : c'est son
  /// équipe qui a changé, et l'invitation lui appartient. La charge ne porte
  /// ni l'identifiant du compte invité, ni la donnée d'un autre compte.
  void _announceInvitation({
    required String callerId,
    required String teamId,
    required TeamRole role,
  }) {
    dispatcher?.emit(
      userId: callerId,
      event: WebhookEvent.teamInvitationSent,
      data: <String, Object?>{'team_id': teamId, 'role': role.name},
    );
  }

  /// Change le rôle de [userId] dans l'équipe [teamId].
  ///
  /// Seul le propriétaire change les rôles, et le rôle du propriétaire
  /// lui-même ne se change pas.
  Future<TeamMember> changeRole({
    required String teamId,
    required String callerId,
    required String userId,
    required TeamRole role,
  }) async {
    await _requireOwner(
      teamId: teamId,
      callerId: callerId,
      action: 'changer les rôles',
    );
    _requireAssignableRole(role);

    final TeamMember? target = await _database.findMember(
      teamId: teamId,
      userId: userId,
    );
    if (target == null) throw const NotFoundException();
    if (target.role == TeamRole.owner) {
      throw const ConflictException(
        message:
            'Le rôle du propriétaire de l\'équipe ne peut pas être modifié : '
            'supprimez l\'équipe si vous voulez repartir de zéro.',
      );
    }

    final TeamMember? updated = await _database.changeMemberRole(
      teamId: teamId,
      userId: userId,
      role: role,
    );
    if (updated == null) throw const NotFoundException();
    return updated;
  }

  /// Retire [userId] de l'équipe [teamId].
  ///
  /// Le propriétaire retire un membre, un membre quitte l'équipe lui-même.
  Future<void> removeMember({
    required String teamId,
    required String callerId,
    required String userId,
  }) async {
    final TeamMember caller = await _requireMember(
      teamId: teamId,
      callerId: callerId,
    );
    final bool isSelf = caller.userId == userId;
    if (!isSelf && caller.role != TeamRole.owner) {
      throw const ForbiddenException(
        message: 'Seul le propriétaire de l\'équipe peut retirer un membre.',
      );
    }

    final TeamMember? target = await _database.findMember(
      teamId: teamId,
      userId: userId,
    );
    if (target == null) throw const NotFoundException();
    if (target.role == TeamRole.owner) {
      throw const ConflictException(
        message:
            'Le propriétaire ne peut pas quitter son équipe : '
            'supprimez l\'équipe.',
      );
    }

    await _database.removeMember(teamId: teamId, userId: userId);
  }

  /// Supprime l'équipe [teamId]. Seul son propriétaire le peut.
  Future<void> deleteTeam({
    required String teamId,
    required String callerId,
  }) async {
    await _requireOwner(
      teamId: teamId,
      callerId: callerId,
      action: 'supprimer l\'équipe',
    );
    final bool deleted = await _database.deleteTeam(teamId: teamId);
    if (!deleted) throw const NotFoundException();
  }

  /// Le membre [callerId] de l'équipe [teamId].
  ///
  /// Une équipe qui n'existe pas et une équipe dont l'appelant n'est pas
  /// membre répondent la même chose : un 404, pour ne jamais divulguer
  /// l'existence d'une équipe.
  Future<TeamMember> _requireMember({
    required String teamId,
    required String callerId,
  }) async {
    final TeamMember? member = await _database.findMember(
      teamId: teamId,
      userId: callerId,
    );
    if (member == null) throw const NotFoundException();
    return member;
  }

  /// Le propriétaire de l'équipe [teamId].
  Future<TeamMember> _requireOwner({
    required String teamId,
    required String callerId,
    required String action,
  }) async {
    final TeamMember member = await _requireMember(
      teamId: teamId,
      callerId: callerId,
    );
    if (member.role != TeamRole.owner) {
      throw ForbiddenException(
        message: 'Seul le propriétaire de l\'équipe peut $action.',
      );
    }
    return member;
  }

  /// Le magasin des invitations, quand il est câblé.
  ///
  /// Sans magasin, le chemin par courriel n'existe pas sur ce serveur : le
  /// service le dit franchement plutôt que d'accepter une invitation qu'il
  /// ne pourrait pas garder.
  TeamInvitationStore _requireInvitationStore() {
    final TeamInvitationStore? store = invitations;
    if (store == null) {
      throw const ServiceUnavailableException(
        message:
            'Les invitations par courriel ne sont pas configurées sur ce '
            'serveur.',
      );
    }
    return store;
  }

  /// Vérifie qu'il reste un siège à offrir dans l'équipe [teamId].
  ///
  /// Un membre invité occupe un siège, et une invitation en attente en
  /// tient un aussi : le propriétaire ne propose pas une place qui n'existe
  /// pas. L'acceptation vérifiera les sièges une seconde fois.
  Future<void> _requireFreeSeat({
    required String teamId,
    required String callerId,
  }) async {
    final SubscriptionPlan plan = await _planOf(callerId);
    final int maxSeats = PlanDefinition.of(plan).quota.maxSeats;

    int used = 0;
    final List<TeamMember> members = await _database.listMembers(
      teamId: teamId,
    );
    for (final TeamMember member in members) {
      if (member.role != TeamRole.owner) used++;
    }
    final List<TeamInvitationRecord> pending = await _requireInvitationStore()
        .listByTeam(teamId: teamId);
    for (final TeamInvitationRecord invitation in pending) {
      if (invitation.isPendingAt(_now())) used++;
    }

    if (used >= maxSeats) throw _seatLimitExceeded(plan, maxSeats);
  }

  /// L'invitation en attente que porte le jeton [token].
  ///
  /// Renvoie `null` quand le jeton est inconnu, falsifié, expiré, révoqué ou
  /// déjà accepté : les cinq cas doivent être indiscernables de l'extérieur,
  /// pour ne pas dire à un tiers qu'une invitation a existé.
  Future<TeamInvitationRecord?> _resolveInvitation(String token) async {
    final String? id = _identifierOfInvitationToken(token);
    if (id == null) return null;
    final TeamInvitationRecord? record = await _requireInvitationStore()
        .findById(id);
    if (record == null) return null;
    if (!_sameDigest(record.tokenHash, hashTeamInvitationToken(token))) {
      return null;
    }
    if (!record.isPendingAt(_now())) return null;
    return record;
  }

  /// La formule du compte [userId].
  ///
  /// La lecture vient de la composition : le service ne connaît pas le
  /// fichier des formules. Une formule inconnue vaut « Gratuit ».
  Future<SubscriptionPlan> _planOf(String userId) async {
    final String? raw = await _database.planLookup(userId);
    return _parsePlan(raw);
  }

  /// La formule correspondant au nom [raw].
  ///
  /// Le nom peut être celui de l'énumération (`studio`) ou celui affiché par
  /// l'interface (`Studio`) : la comparaison ignore la casse, les accents et
  /// la parenthèse de la formule annuelle.
  static SubscriptionPlan _parsePlan(String? raw) {
    if (raw == null) return _freePlan;
    final String normalized = _normalize(raw);
    for (final SubscriptionPlan plan in SubscriptionPlan.values) {
      if (_normalize(plan.name) == normalized) return plan;
      if (_normalize(PlanDefinition.of(plan).displayName) == normalized) {
        return plan;
      }
    }
    return _freePlan;
  }

  /// Le nom [value] réduit à ses lettres et à ses chiffres.
  static String _normalize(String value) {
    final String base = value.toLowerCase().split('(').first;
    final StringBuffer buffer = StringBuffer();
    for (final String character in base.split('')) {
      final String folded = _accents[character] ?? character;
      if (RegExp('[a-z0-9]').hasMatch(folded)) buffer.write(folded);
    }
    return buffer.toString();
  }

  /// Le rôle [role] peut être attribué à un membre.
  ///
  /// Le propriétaire est le créateur de l'équipe : son rôle ne s'attribue
  /// pas.
  static void _requireAssignableRole(TeamRole role) {
    if (role == TeamRole.owner) {
      throw const ValidationException(
        field: 'role',
        message:
            'Le rôle « propriétaire » est réservé au créateur de l\'équipe.',
      );
    }
  }

  /// L'adresse [email], normalisée et vérifiée.
  ///
  /// La normalisation rend l'adresse comparable : `Alice@Exemple.COM ` et
  /// `alice@exemple.com` sont la même adresse.
  static String _readEmail(String email) {
    final String address = _normalizeEmail(email);
    if (!_isEmailAddress(address)) {
      throw const ValidationException(
        field: 'email',
        message: 'L\'adresse électronique de l\'invité est invalide.',
      );
    }
    return address;
  }

  /// L'adresse [email] normalisée : minuscules, espaces coupés.
  static String _normalizeEmail(String email) => email.trim().toLowerCase();

  /// L'adresse [address] ressemble-t-elle à une adresse électronique.
  ///
  /// La vérification est volontairement simple : un arobase, un domaine avec
  /// un point, pas d'espace. Elle refuse les adresses manifestement fausses
  /// sans prétendre connaître le format de toutes les adresses possibles.
  static bool _isEmailAddress(String address) {
    if (address.isEmpty || address.length > maxInvitationEmailLength) {
      return false;
    }
    final int at = address.indexOf('@');
    if (at <= 0 || at != address.lastIndexOf('@')) return false;
    final String domain = address.substring(at + 1);
    if (domain.length < 3 || !domain.contains('.')) return false;
    if (domain.startsWith('.') || domain.endsWith('.')) return false;
    return !address.contains(' ');
  }

  /// L'erreur refusant une invitation au-delà des sièges de la formule.
  ///
  /// La formule Studio est la plus haute : une équipe pleine est un conflit
  /// (409). Une formule plus basse exige un changement de formule (402).
  static AppException _seatLimitExceeded(SubscriptionPlan plan, int maxSeats) {
    final String seats = maxSeats > 1 ? '$maxSeats sièges' : '$maxSeats siège';
    if (plan == SubscriptionPlan.studio) {
      return ConflictException(
        message:
            'La formule Studio est limitée à $seats par équipe : '
            'retirez un membre avant d\'inviter quelqu\'un d\'autre.',
        details: <String, Object?>{
          'limit': maxSeats,
          'plan': PlanDefinition.of(plan).displayName,
        },
      );
    }
    return PlanLimitException(
      message:
          'Votre formule ${PlanDefinition.of(plan).displayName} ne comporte '
          'que $seats par équipe : la formule Studio est nécessaire pour '
          'inviter un membre de plus.',
      details: <String, Object?>{
        'limit': maxSeats,
        'plan': PlanDefinition.of(plan).displayName,
        'required_plan': PlanDefinition.of(SubscriptionPlan.studio).displayName,
      },
    );
  }

  /// La durée de vie demandée, en heures, bornée par le contrat.
  int _readInvitationLifetimeHours(int? lifetimeHours) {
    final int hours = lifetimeHours ?? defaultTeamInvitationLifetimeHours;
    if (hours < minTeamInvitationLifetimeHours ||
        hours > maxTeamInvitationLifetimeHours) {
      throw ValidationException(
        field: 'expires_in_hours',
        message:
            'La durée de vie de l\'invitation doit être comprise entre '
            '$minTeamInvitationLifetimeHours et '
            '$maxTeamInvitationLifetimeHours heures.',
      );
    }
    return hours;
  }

  /// Le jeton en clair, fait de son identifiant et d'un secret.
  ///
  /// Le secret vient de `random_secret.dart` : il porte 256 bits de hasard,
  /// le jeton n'est donc pas devinable.
  String _presentInvitationToken(String id) {
    return '$teamInvitationTokenPrefix$teamInvitationTokenSeparator$id'
        '$teamInvitationTokenSeparator${generateRandomSecret()}';
  }

  /// L'identifiant porté par le jeton présenté, `null` quand le jeton est
  /// mal formé.
  String? _identifierOfInvitationToken(String presentedToken) {
    final String trimmed = presentedToken.trim();
    final String head =
        '$teamInvitationTokenPrefix'
        '$teamInvitationTokenSeparator';
    if (!trimmed.startsWith(head)) return null;
    final String rest = trimmed.substring(head.length);
    final int separator = rest.indexOf(teamInvitationTokenSeparator);
    if (separator <= 0 || separator == rest.length - 1) return null;
    return rest.substring(0, separator);
  }

  DateTime _now() => _clock().toUtc();
}

/// L'empreinte d'un jeton d'invitation d'équipe.
///
/// L'empreinte est le SHA-256 du jeton complet, en hexadécimal : elle ne
/// permet pas de retrouver le jeton.
String hashTeamInvitationToken(String presentedToken) {
  return sha256.convert(utf8.encode(presentedToken)).toString();
}

/// Indique si les deux empreintes [left] et [right] sont identiques.
///
/// La comparaison ne s'arrête pas au premier caractère différent : elle
/// parcourt toute la chaîne, pour que le temps de réponse ne révèle pas
/// combien de caractères sont justes.
bool _sameDigest(String left, String right) {
  if (left.length != right.length) return false;
  int difference = 0;
  for (int index = 0; index < left.length; index++) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}
