import 'kdp_record.dart';

/// La marque d'un champ que la copie d'une trace ne remplace pas.
///
/// La marque distingue « le champ est absent de la copie » de « le champ
/// est présent et vide » : une reprise de dépôt efface ainsi le motif de
/// l'échec précédent.
const Object _unset = Object();

/// L'état d'un dépôt de dossier auprès d'Amazon KDP.
///
/// L'état décrit ce qu'Amazon a répondu, jamais ce que la plateforme
/// suppose : un dépôt qui n'a pas de réponse reste en attente, un dépôt
/// refusé porte la liste des problèmes d'Amazon.
enum KdpDepositStatus {
  /// Le dossier a été remis à Amazon : son verdict n'est pas encore connu.
  ///
  /// L'état couvre l'instant où le dépôt est écrit et celui où Amazon
  /// n'a pas encore répondu. Un dépôt en attente n'est jamais relancé :
  /// l'appel est peut-être encore en vol, et Amazon a peut-être déjà reçu
  /// le dossier. Il se réconcilie quand l'auteur sait ce qui s'est passé.
  pending('pending'),

  /// Amazon a accepté le dossier : il entre dans son circuit de relecture.
  ///
  /// Un dépôt accepté n'est jamais remis à Amazon une seconde fois.
  submitted('submitted'),

  /// Amazon a refusé le dossier.
  ///
  /// La liste des problèmes est jointe au dépôt : elle dit à l'auteur ce
  /// qu'il doit corriger, comme le fait le contrôle de soumission.
  rejected('rejected'),

  /// Le dépôt a échoué : le dossier n'est jamais parti, ou Amazon a
  /// refusé la demande.
  ///
  /// Le motif de l'échec est joint au dépôt et le dépôt peut être relancé.
  failed('failed'),

  /// L'issue du dépôt est inconnue : le dossier est parti, Amazon n'a pas
  /// répondu.
  ///
  /// Amazon a peut-être enregistré la soumission : relancer le dossier
  /// produirait une seconde fiche KDP pour un seul livre. Le dépôt n'est
  /// donc jamais relancé tout seul : l'auteur réconcilie le dépôt quand il
  /// sait ce qui s'est passé.
  unknown('unknown');

  const KdpDepositStatus(this.key);

  /// Le nom technique de l'état.
  final String key;
}

/// La trace d'un dépôt de dossier auprès d'Amazon KDP.
///
/// La trace est la reprise du dépôt : elle porte l'identifiant du dépôt,
/// la publication qui part, l'état, l'identifiant du dépôt chez Amazon,
/// la liste des problèmes et le motif d'un échec technique.
///
/// La trace locale est la seule protection contre le double envoi : le
/// contrat d'Amazon ne porte pas de clé d'idempotence, et un dossier
/// renvoyé deux fois y crée deux fiches KDP.
final class KdpDeposit {
  /// Crée une trace de dépôt.
  const KdpDeposit({
    required this.id,
    required this.publicationId,
    required this.userId,
    required this.status,
    required this.issues,
    required this.attempts,
    required this.createdAt,
    required this.updatedAt,
    this.amazonSubmissionId,
    this.failureReason,
  });

  /// L'identifiant du dépôt.
  final String id;

  /// La publication préparée qui part vers Amazon.
  final String publicationId;

  /// Le compte qui a demandé le dépôt.
  final String userId;

  /// L'état du dépôt.
  final KdpDepositStatus status;

  /// L'identifiant du dépôt chez Amazon, `null` tant qu'Amazon n'a pas
  /// accepté le dossier.
  final String? amazonSubmissionId;

  /// Les problèmes relevés.
  ///
  /// La liste porte le refus d'Amazon quand il y en a un, et le résultat du
  /// contrôle de soumission quand le dossier n'a pas pu partir. Elle vide
  /// pour un dépôt accepté.
  final List<KdpIssue> issues;

  /// Le motif d'un échec technique, `null` quand le dépôt n'a pas échoué.
  final String? failureReason;

  /// Le nombre de tentatives faites auprès d'Amazon.
  final int attempts;

  /// L'horodatage de la création du dépôt.
  final DateTime createdAt;

  /// L'horodatage de la dernière mise à jour du dépôt.
  final DateTime updatedAt;

  /// Vrai quand Amazon a accepté le dossier.
  bool get isSubmitted => status == KdpDepositStatus.submitted;

  /// Vrai quand le dépôt peut être remis à Amazon une seconde fois.
  ///
  /// Seuls un dépôt en échec — le dossier n'est jamais parti — et un
  /// dossier refusé par Amazon se relancent, ce dernier après que l'auteur
  /// a corrigé son dossier.
  ///
  /// Un dépôt en attente ne se relance pas : l'appel est peut-être encore
  /// en vol, ou le serveur est tombé avant d'écrire le verdict, et Amazon a
  /// peut-être déjà reçu le dossier. Un dépôt accepté ne se relance jamais,
  /// et un dépôt dont l'issue est inconnue ne se relance pas non plus.
  bool get isResumable =>
      status == KdpDepositStatus.failed || status == KdpDepositStatus.rejected;

  /// Une copie de la trace avec les champs remplacés.
  ///
  /// Les champs absents de [copyWith] gardent leur valeur : la trace n'est
  /// jamais modifiée en place. Les deux champs facultatifs se vident quand
  /// on leur passe explicitement `null` : une reprise de dépôt efface ainsi
  /// le motif de l'échec précédent.
  KdpDeposit copyWith({
    KdpDepositStatus? status,
    Object? amazonSubmissionId = _unset,
    List<KdpIssue>? issues,
    Object? failureReason = _unset,
    int? attempts,
    DateTime? updatedAt,
  }) {
    return KdpDeposit(
      id: id,
      publicationId: publicationId,
      userId: userId,
      status: status ?? this.status,
      amazonSubmissionId: identical(amazonSubmissionId, _unset)
          ? this.amazonSubmissionId
          : amazonSubmissionId as String?,
      issues: issues ?? this.issues,
      failureReason: identical(failureReason, _unset)
          ? this.failureReason
          : failureReason as String?,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// La représentation JSON de la trace.
  ///
  /// Les problèmes sont rendus dans la forme du contrôle de soumission :
  /// un refus d'Amazon se lit comme celui du contrôle local.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'publication_id': publicationId,
      'user_id': userId,
      'status': status.key,
      'amazon_submission_id': amazonSubmissionId,
      'issues': <Object?>[for (final KdpIssue issue in issues) issue.toJson()],
      'failure_reason': failureReason,
      'attempts': attempts,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}
