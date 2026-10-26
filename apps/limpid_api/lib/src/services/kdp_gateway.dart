import '../db/kdp_record.dart';
import '../errors/app_exception.dart';

/// La demande de dépôt d'un dossier préparé auprès d'Amazon KDP.
///
/// La demande porte les métadonnées de la fiche produit et l'adresse des
/// deux fichiers déposés. Les adresses sont signées et expirent : Amazon
/// les lit pendant la fenêtre de dépôt.
///
/// Les adresses ne viennent jamais de l'appelant : elles sont produites par
/// le stockage de la plateforme, à partir des clés de la publication
/// préparée.
final class KdpSubmissionRequest {
  /// Crée une demande de dépôt.
  const KdpSubmissionRequest({
    required this.depositId,
    required this.title,
    required this.author,
    required this.description,
    required this.keywords,
    required this.categories,
    required this.language,
    required this.epubUrl,
    required this.pdfUrl,
    this.isbn,
    this.publisher,
  });

  /// L'identifiant du dépôt, qui est la clé d'idempotence **locale**.
  ///
  /// Le contrat d'Amazon ne porte pas de clé d'idempotence : cet
  /// identifiant relie la trace locale du dépôt à la demande, il ne
  /// protège Amazon de rien.
  final String depositId;

  /// Le titre de l'ouvrage.
  final String title;

  /// Le nom de l'auteur.
  final String author;

  /// Le résumé de l'ouvrage.
  final String description;

  /// Les mots-clés de la fiche produit.
  final List<String> keywords;

  /// Les catégories de la fiche produit.
  final List<String> categories;

  /// L'ISBN de l'édition imprimée, `null` quand l'ouvrage n'en porte pas.
  final String? isbn;

  /// La langue de l'ouvrage.
  final String language;

  /// L'éditeur de l'ouvrage, `null` quand l'ouvrage n'en porte pas.
  final String? publisher;

  /// L'adresse signée du fichier du livre électronique.
  final String epubUrl;

  /// L'adresse signée du fichier du livre imprimé.
  final String pdfUrl;
}

/// L'échéance partagée d'une chaîne d'appels auprès d'Amazon.
///
/// Le budget vient de la requête HTTP : la passerelle en tire une
/// échéance unique, que tous les appels de la chaîne partagent. Un appel
/// reçoit le temps qui reste, et il n'est pas envoyé quand il n'y en a
/// plus : la chaîne entière ne peut donc pas dépasser le budget de la
/// requête.
final class KdpCallBudget {
  /// Crée une échéance qui expire [budget] après [now].
  KdpCallBudget({required Duration budget, required DateTime now})
    : _deadline = now.add(budget);

  final DateTime _deadline;

  /// L'instant où la chaîne n'a plus de temps.
  DateTime get deadline => _deadline;

  /// Le temps qui reste avant l'échéance, à l'instant [now].
  ///
  /// Le temps restant ne descend jamais sous zéro : un appel ne peut pas
  /// se voir accorder un délai négatif.
  Duration remainingAt(DateTime now) {
    final Duration left = _deadline.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// Le verdict d'un dépôt auprès d'Amazon.
///
/// Le dépôt n'échoue jamais par une exception : Amazon répond par un
/// verdict, et l'absence de réponse est elle-même un verdict. Les états
/// correspondent aux issues du cycle : l'acceptation, le refus motivé,
/// l'échec qui laisse le dossier intact, et l'issue incertaine.
sealed class KdpSubmissionOutcome {
  /// Crée un verdict.
  const KdpSubmissionOutcome();
}

/// Amazon a accepté le dossier.
final class KdpSubmissionAccepted extends KdpSubmissionOutcome {
  /// Crée un verdict d'acceptation.
  const KdpSubmissionAccepted(this.submissionId);

  /// L'identifiant du dépôt chez Amazon.
  final String submissionId;
}

/// Amazon a refusé le dossier.
///
/// Le refus n'est pas une erreur technique : il est rendu à l'auteur comme
/// une liste de problèmes, dans la forme du contrôle de soumission.
final class KdpSubmissionRefused extends KdpSubmissionOutcome {
  /// Crée un verdict de refus.
  KdpSubmissionRefused(List<KdpIssue> issues)
    : issues = List<KdpIssue>.unmodifiable(issues);

  /// Les problèmes relevés par Amazon.
  final List<KdpIssue> issues;
}

/// Le dossier n'a pas pu être instruit : il n'est jamais parti.
///
/// Amazon n'a rien reçu : rien ne dit qu'il ait créé une soumission, et le
/// dossier peut être relancé.
final class KdpSubmissionUnavailable extends KdpSubmissionOutcome {
  /// Crée un verdict d'indisponibilité.
  const KdpSubmissionUnavailable(this.reason);

  /// Le motif de l'échec, écrit pour l'auteur.
  final String reason;
}

/// Le dossier est parti, mais l'issue n'est pas connue.
///
/// Amazon a peut-être enregistré la soumission : le dossier ne repart pas
/// tout seul. L'auteur doit dire ce qui s'est passé avant que le dépôt
/// puisse reprendre.
final class KdpSubmissionUnknown extends KdpSubmissionOutcome {
  /// Crée un verdict d'issue incertaine.
  const KdpSubmissionUnknown(this.reason);

  /// Le motif de l'incertitude, écrit pour l'auteur.
  final String reason;
}

/// La capacité de déposer un dossier auprès d'Amazon KDP.
///
/// Le port est la seule porte de sortie vers Amazon : la suite de tests le
/// remplace par une double en mémoire, et le service de dépôt ne connaît
/// ni le transport HTTP ni les identifiants de l'intégration.
abstract interface class KdpGateway {
  /// Dépose le dossier [request] auprès d'Amazon.
  ///
  /// La méthode ne lève jamais : elle rend le verdict d'Amazon, ou le motif
  /// de l'échec quand Amazon n'a pas répondu. Un dossier parti dont
  /// l'issue est incertaine rend un [KdpSubmissionUnknown] : le service ne
  /// le relancera pas.
  Future<KdpSubmissionOutcome> submit(KdpSubmissionRequest request);
}

/// Une [KdpGateway] qui tient lieu d'intégration Amazon non configurée.
///
/// Un serveur sans identifiants Amazon sert quand même les autres routes :
/// celle du dépôt répond un refus propre au lieu de préparer un appel qui
/// échouerait.
final class UnavailableKdpGateway implements KdpGateway {
  /// Crée une passerelle indisponible.
  const UnavailableKdpGateway();

  @override
  Future<KdpSubmissionOutcome> submit(KdpSubmissionRequest request) =>
      throw const ServiceUnavailableException(
        message:
            "La distribution Amazon KDP n'est pas configurée sur ce serveur.",
      );
}

/// Les motifs d'un dépôt qui n'a pas abouti.
///
/// Les motifs sont écrits pour l'auteur : ils disent ce qui s'est passé et
/// si le dossier est parti. Aucun ne promet qu'un simple clic suffit quand
/// relancer ne sert à rien, et aucun ne dit « relancez » quand Amazon n'a
/// rien reçu.
abstract final class KdpDepositFailures {
  /// Amazon a refusé les identifiants de l'intégration.
  ///
  /// Le jeton n'a pas pu être obtenu : relancer le dépôt sans corriger la
  /// configuration échouerait de la même façon.
  static const String unauthorized =
      "Amazon a refusé les identifiants de l'intégration. Le dossier n'a "
      'pas été transmis : un administrateur doit vérifier la configuration.';

  /// Le compte Amazon KDP est bloqué ou a atteint son quota.
  static const String accountBlocked =
      'Le compte Amazon KDP est bloqué ou a atteint son quota de dépôts. '
      "Le dossier n'a pas été transmis.";

  /// Amazon bride les dépôts.
  static const String rateLimited =
      "Amazon limite les dépôts pour le moment. Le dossier n'a pas été "
      'transmis : patientez avant de réessayer.';

  /// Amazon a renvoyé une erreur de son côté.
  static const String serverError =
      "Amazon a rencontré une erreur de son côté. Le dossier n'a pas été "
      'transmis.';

  /// Le jeton n'a pas pu être obtenu dans le temps imparti.
  static const String tokenTimeout =
      "Amazon n'a pas répondu à temps. Le dossier n'a pas été transmis : il "
      'peut être relancé.';

  /// Le service d'Amazon est injoignable : le jeton n'a pas pu être obtenu.
  static const String tokenUnreachable =
      "Le service de distribution d'Amazon est injoignable. Le dossier n'a "
      'pas été transmis : il peut être relancé.';

  /// La réponse du service d'autorisation d'Amazon est illisible.
  static const String tokenUnreadable =
      "La réponse d'Amazon est illisible. Le dossier n'a pas été transmis : "
      'il peut être relancé.';

  /// La requête n'a plus de temps pour déposer le dossier.
  static const String budgetExhausted =
      "La requête n'a plus de temps pour déposer le dossier auprès d'Amazon. "
      "Le dossier n'a pas été transmis : il peut être relancé.";

  /// Le dossier est parti, mais Amazon n'a pas répondu à temps.
  static const String unknownTimeout =
      "Amazon n'a pas répondu à temps. L'issue du dépôt est incertaine : "
      'Amazon a peut-être reçu le dossier.';

  /// Le dossier est parti, mais la connexion a été coupée.
  static const String unknownUnreachable =
      "La connexion à Amazon a été coupée. L'issue du dépôt est incertaine : "
      'Amazon a peut-être reçu le dossier.';

  /// Le dossier est parti, mais la réponse d'Amazon est illisible.
  static const String unknownUnreadable =
      "Amazon a traité la demande mais sa réponse est illisible. L'issue du "
      'dépôt est incertaine : Amazon a peut-être reçu le dossier.';

  /// Le dossier est parti, mais Amazon a renvoyé une erreur de son côté.
  ///
  /// Une erreur d'Amazon ne prouve pas que le dossier a été refusé : il a
  /// pu être enregistré avant que la réponse ne se perde.
  static const String unknownServerError =
      "Amazon a renvoyé une erreur après avoir reçu la demande. L'issue du "
      'dépôt est incertaine : Amazon a peut-être reçu le dossier.';

  /// L'auteur a déclaré qu'Amazon n'avait rien reçu du dossier.
  static const String notReceived =
      "Amazon n'a rien reçu de ce dossier : il peut être relancé.";
}
