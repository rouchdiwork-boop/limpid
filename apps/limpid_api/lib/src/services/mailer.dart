import '../config/app_config.dart';
import '../db/team_record.dart';
import '../logging/logger.dart';

/// Le chemin canonique de l'acceptation d'une invitation d'équipe.
///
/// Le lien d'invitation porte ce chemin : il contient le jeton, et le jeton
/// est la seule chose qu'il faut pour accepter.
const String teamInvitationAcceptPath = '/v1/team-invitations';

/// L'adresse publique du service, quand elle n'est pas configurée.
///
/// Le mode « aucun fournisseur de courriel » rend le lien à l'auteur : il lui
/// faut une adresse. En développement, l'API écoute sur le port 8080.
const String defaultPublicBaseUrl = 'http://localhost:8080';

/// Le message qui porte l'invitation d'équipe.
///
/// Le message porte le nom de l'équipe, le rôle, le lien et la date
/// d'expiration. Le **seul** secret qu'il contient est le lien : le lien
/// porte le jeton, c'est tout.
final class TeamInvitationMail {
  /// Crée un message d'invitation.
  const TeamInvitationMail({
    required this.recipient,
    required this.teamName,
    required this.role,
    required this.link,
    required this.expiresAt,
  });

  /// L'adresse de l'invité.
  final String recipient;

  /// Le nom de l'équipe visée.
  final String teamName;

  /// Le rôle accordé à l'invité.
  final TeamRole role;

  /// Le lien d'acceptation.
  ///
  /// Le lien porte le jeton : il n'est jamais rendu une seconde fois.
  final String link;

  /// L'instant d'expiration de l'invitation.
  final DateTime expiresAt;

  /// Le sujet du message, en français.
  String get subject => 'Invitation à rejoindre l\'équipe « $teamName »';

  /// Le corps du message, en français.
  ///
  /// Le corps reprend le nom de l'équipe, le rôle, le lien et la date
  /// d'expiration. Il ne porte aucun autre secret.
  String get body {
    final String date = expiresAt.toUtc().toIso8601String();
    return 'Vous êtes invité à rejoindre l\'équipe « $teamName » '
        'avec le rôle « ${role.label} ».\n\n'
        'Pour accepter, ouvrez ce lien :\n$link\n\n'
        'L\'invitation expire le $date.';
  }
}

/// Le port du courriel.
///
/// Le service des équipes ne parle jamais au fournisseur : il parle à ce
/// port. Deux implémentations coexistent : le journal, quand aucun
/// fournisseur n'est configuré, et le fournisseur HTTP, quand il l'est.
abstract interface class Mailer {
  /// Envoie l'invitation d'équipe à [recipient].
  ///
  /// L'implémentation qui écrit dans le journal ne « sends » rien : elle
  /// consigne le message.
  Future<void> sendTeamInvitation(TeamInvitationMail mail);

  /// Un fournisseur de courriel est-il configuré.
  ///
  /// Quand aucun fournisseur n'est configuré, la route rend le lien
  /// d'invitation **une seule fois**, comme elle rend le jeton d'un partage :
  /// l'auteur le copie et le transmet. Quand le fournisseur est configuré,
  /// le lien part par courriel et n'est plus rendu.
  bool get isConfigured;
}

/// Le lien d'acceptation d'une invitation d'équipe.
///
/// Le lien porte le jeton : c'est le seul secret qu'il contient.
final class TeamInvitationLink {
  /// Crée un lien.
  const TeamInvitationLink(this.value);

  /// L'adresse du lien.
  final String value;

  /// Le lien d'acceptation du jeton [token].
  ///
  /// L'adresse de base [baseUrl] est celle du service public : elle ne se
  /// déduit pas du jeton, et le lien ne se construit qu'avec elle.
  static TeamInvitationLink build({
    required String baseUrl,
    required String token,
  }) {
    final String root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final String path =
        '$teamInvitationAcceptPath/'
        '${Uri.encodeComponent(token)}/accept';
    return TeamInvitationLink('$root$path');
  }

  @override
  String toString() => value;
}

/// Le port du courriel qui écrit dans le journal.
///
/// C'est le mode par défaut : aucun fournisseur n'est configuré, le message
/// est consigné et le lien est rendu à l'auteur. Le journal dit dans quel
/// mode on est — et il ne garde ni le jeton ni l'adresse : le journal
/// retire les champs sensibles par leur nom.
final class LogMailer implements Mailer {
  /// Crée un port qui écrit dans le journal [logger].
  LogMailer({Logger? logger})
    : _logger = logger ?? Logger(level: LogLevel.info);

  final Logger _logger;

  @override
  bool get isConfigured => false;

  @override
  Future<void> sendTeamInvitation(TeamInvitationMail mail) async {
    _logger.info(
      'Invitation d\'équipe écrite dans le journal : aucun fournisseur de '
      'courriel n\'est configuré.',
      <String, Object?>{
        'mode': 'journal',
        'team': mail.teamName,
        'role': mail.role.name,
        'expires_at': mail.expiresAt.toUtc().toIso8601String(),
        // Le champ porte le jeton dans son nom : le journal le retire. Le
        // lien ne passe jamais en clair dans une trace.
        'token_link': mail.link,
      },
    );
  }
}
