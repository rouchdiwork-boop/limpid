import 'package:limpid_core/limpid_core.dart';

import '../auth/auth_context.dart';
import '../db/kdp_database.dart';
import '../db/kdp_deposit_record.dart';
import '../db/kdp_deposit_store.dart';
import '../db/kdp_record.dart';
import '../errors/app_exception.dart';
import 'kdp_gateway.dart';
import 'kdp_reconciliation.dart';

/// Le service de dépôt du dossier de publication auprès d'Amazon KDP.
///
/// Le service reprend le dossier préparé par la publication : il relit la
/// trace de la préparation, refuse un dossier que le contrôle de soumission
/// a bloqué, remet les deux fichiers à Amazon et consigne le verdict.
///
/// Le contrat d'Amazon ne porte pas de clé d'idempotence : Amazon peut
/// créer deux soumissions pour un même dossier si la plateforme le lui
/// renvoie deux fois. C'est la trace locale qui l'empêche : un dépôt
/// accepté n'est jamais remis à Amazon, et un dépôt parti — en attente ou
/// d'issue inconnue — n'est jamais relancé tout seul. L'auteur réconcilie
/// le dépôt quand il sait ce qui s'est passé.
final class KdpPublishingService {
  /// Crée un service.
  ///
  /// [clock] rend l'heure injectable : les tests font passer le temps sans
  /// attendre.
  KdpPublishingService({
    required this.publications,
    required this.deposits,
    required this.gateway,
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  /// Les publications préparées, que le service relit pour savoir ce qui
  /// part.
  final KdpDatabase publications;

  /// La trace des dépôts.
  final KdpDepositStore deposits;

  /// La porte de sortie vers Amazon.
  final KdpGateway gateway;

  final DateTime Function() _clock;

  /// La durée de validité des adresses des fichiers déposés.
  ///
  /// Les adresses sont signées : elles expirent, et Amazon les lit pendant
  /// la fenêtre du dépôt.
  static const Duration fileUrlExpiry = Duration(hours: 6);

  /// Le message rendu à l'auteur quand l'issue d'un dépôt est inconnue.
  ///
  /// Le message dit ce qu'il faut faire : regarder la console KDP d'Amazon,
  /// puis confirmer ce qui s'est passé. Il ne propose jamais de relancer
  /// le dossier.
  static const String unknownOutcomeMessage =
      "L'issue de ce dépôt est incertaine : Amazon a peut-être reçu le "
      "dossier. Vérifiez la console KDP d'Amazon, puis confirmez ce qui "
      "s'est passé.";

  /// Le message rendu à l'auteur quand un dépôt est encore en cours.
  ///
  /// Le message invite à attendre la fin de la tentative : le dossier peut
  /// déjà être chez Amazon.
  static const String pendingOutcomeMessage =
      'Ce dossier est déjà en cours de dépôt chez Amazon : le renvoyer '
      'créerait une seconde fiche KDP. Attendez la fin de la tentative, '
      "puis vérifiez la console KDP d'Amazon.";

  static final UlidGenerator _ulid = UlidGenerator();

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Dépose le dossier de la publication [publicationId] auprès d'Amazon.
  ///
  /// Le dépôt est rendu à l'auteur dans tous les cas : accepté, refusé par
  /// Amazon ou en échec. Un refus n'est pas une erreur technique : il porte
  /// la liste des problèmes, dans la forme du contrôle de soumission.
  ///
  /// Un dossier que le contrôle de soumission a bloqué n'est pas déposé :
  /// la route répond un conflit qui porte les mêmes problèmes.
  ///
  /// Un dépôt dont l'issue n'est pas connue n'est **pas** relancé : il est
  /// en attente, ou Amazon a peut-être déjà reçu le dossier, et le renvoyer
  /// créerait une seconde fiche KDP. La route répond un conflit qui
  /// demande à l'auteur de réconcilier le dépôt.
  ///
  /// Le dépôt reprend un dossier déjà préparé : la formule du compte a été
  /// vérifiée par la préparation, elle n'est pas revérifiée ici.
  Future<KdpDeposit> deposit({
    required AuthContext auth,
    required String publicationId,
  }) async {
    final KdpPublication? publication = await publications.findPublication(
      publicationId: publicationId,
      userId: auth.userId,
    );
    if (publication == null) {
      throw const NotFoundException(
        message: "Cette publication n'existe pas ou n'est plus accessible.",
      );
    }

    final KdpDeposit? existing = await deposits.findDepositByPublication(
      publicationId: publicationId,
      userId: auth.userId,
    );
    if (existing != null && existing.isSubmitted) {
      // Amazon a déjà accepté ce dossier : il ne le reçoit pas deux fois.
      return existing;
    }
    if (existing != null && !existing.isResumable) {
      // Le dossier est en cours de dépôt, ou son issue n'est pas connue :
      // Amazon a peut-être enregistré la soumission. Le renvoyer créerait
      // une seconde fiche KDP.
      throw _uncertainOutcome(existing);
    }

    if (!publication.isReady) {
      throw ConflictException(
        message:
            "Ce dossier n'est pas prêt pour Amazon : le contrôle de "
            'soumission a relevé des problèmes à corriger avant le dépôt.',
        details: <String, Object?>{
          'issues': <Object?>[
            for (final KdpIssue issue in publication.issues) issue.toJson(),
          ],
        },
      );
    }

    final String depositId = existing?.id ?? _ulid.generate().value;
    final KdpSubmissionRequest request = await _request(publication, depositId);
    final KdpDeposit started;
    try {
      started = await _start(publication, existing, depositId);
    } on _AlreadySubmitted catch (taken) {
      // Une autre demande a déposé le dossier et Amazon l'a accepté :
      // cette demande ne le renvoie pas, elle rend le dépôt déjà connu.
      return taken.deposit;
    }
    final KdpSubmissionOutcome outcome = await gateway.submit(request);
    return _record(started, outcome);
  }

  /// Ouvre la tentative de dépôt, en refusant la course d'une autre.
  ///
  /// Deux demandes concurrentes pour la même publication se lisent la même
  /// trace vide : la seconde écriture est refusée par la base. La demande
  /// concurrente devient alors un conflit lisible, jamais un second envoi
  /// du dossier chez Amazon.
  ///
  /// Deux reprises concurrentes d'un même dépôt en échec se lisent la même
  /// trace : la reprise ne s'applique que si la trace est encore dans
  /// l'état qu'elle avait à la lecture. Une seule des deux demandes
  /// repart, l'autre refuse.
  Future<KdpDeposit> _start(
    KdpPublication publication,
    KdpDeposit? existing,
    String depositId,
  ) async {
    try {
      return await _startDeposit(publication, existing, depositId);
    } on Object {
      final KdpDeposit? concurrent = await _concurrentDeposit(
        publicationId: publication.id,
        userId: publication.userId,
      );
      if (concurrent == null) rethrow;
      if (concurrent.isSubmitted) {
        // L'autre demande a obtenu l'acceptation d'Amazon : le dossier
        // est déjà chez lui, celui-ci ne le renvoie pas.
        throw _AlreadySubmitted(concurrent);
      }
      throw _uncertainOutcome(concurrent);
    }
  }

  /// Le dépôt écrit pour la même publication pendant la tentative.
  ///
  /// La lecture peut échouer elle aussi : elle rend alors `null`, et
  /// l'erreur d'origine est relancée.
  Future<KdpDeposit?> _concurrentDeposit({
    required String publicationId,
    required String userId,
  }) async {
    try {
      return await deposits.findDepositByPublication(
        publicationId: publicationId,
        userId: userId,
      );
    } on Object {
      return null;
    }
  }

  /// Le dépôt [depositId] du compte [auth], `null` quand il n'existe pas.
  Future<KdpDeposit?> find({
    required AuthContext auth,
    required String depositId,
  }) {
    return deposits.findDeposit(depositId: depositId, userId: auth.userId);
  }

  /// Les dépôts du compte [auth], les plus récents d'abord.
  Future<List<KdpDeposit>> list({required AuthContext auth}) {
    return deposits.listDeposits(userId: auth.userId);
  }

  /// Réconcilie un dépôt dont l'issue n'est pas connue.
  ///
  /// L'auteur déclare ce qui s'est passé chez Amazon : soit la soumission
  /// existe et le dépôt devient accepté, soit Amazon n'a rien reçu et le
  /// dossier peut repartir. La déclaration est toujours explicite : rien ne
  /// relance un dossier sans que l'auteur l'ait demandé.
  ///
  /// Un dépôt en attente se réconcilie aussi : c'est le cas du serveur
  /// tombé avant d'écrire le verdict, où Amazon a peut-être déjà reçu le
  /// dossier.
  Future<KdpDeposit> reconcile({
    required AuthContext auth,
    required String depositId,
    required KdpReconciliation reconciliation,
  }) async {
    final KdpDeposit? deposit = await deposits.findDeposit(
      depositId: depositId,
      userId: auth.userId,
    );
    if (deposit == null) {
      throw const NotFoundException(
        message: "Ce dépôt n'existe pas ou n'est plus accessible.",
      );
    }
    final KdpDepositStatus expected = deposit.status;
    if (expected != KdpDepositStatus.unknown &&
        expected != KdpDepositStatus.pending) {
      throw ConflictException(
        message:
            "Ce dépôt n'a pas d'issue incertaine : il n'y a rien à "
            'réconcilier.',
        details: <String, Object?>{
          'deposit_id': deposit.id,
          'status': deposit.status.key,
        },
      );
    }
    final KdpDeposit reconciled = switch (reconciliation.outcome) {
      KdpReconciliationOutcome.submitted => _confirmed(deposit, reconciliation),
      KdpReconciliationOutcome.notReceived => deposit.copyWith(
        status: KdpDepositStatus.failed,
        failureReason: KdpDepositFailures.notReceived,
        updatedAt: _clock(),
      ),
    };
    final bool applied = await deposits.updateDepositIfStatus(
      reconciled,
      expectedStatus: expected,
    );
    if (!applied) {
      // La trace a changé entre-temps : une autre réconciliation a déjà
      // tranché. Deux déclarations contraires ne s'appliquent pas l'une
      // après l'autre : le dossier repartirait une seconde fois.
      throw ConflictException(
        message:
            'Ce dépôt a déjà été réconcilié : sa trace a changé depuis la '
            'lecture.',
        details: <String, Object?>{
          'deposit_id': deposit.id,
          'status': expected.key,
        },
      );
    }
    return reconciled;
  }

  /// La demande de dépôt du dossier [publication].
  ///
  /// Les adresses des fichiers sont signées par le stockage de la
  /// plateforme : elles ne viennent jamais de l'appelant.
  Future<KdpSubmissionRequest> _request(
    KdpPublication publication,
    String depositId,
  ) async {
    final String epubUrl = await publications.artefacts.presignedUrl(
      key: publication.epubKey,
      expires: fileUrlExpiry,
    );
    final String pdfUrl = await publications.artefacts.presignedUrl(
      key: publication.pdfKey,
      expires: fileUrlExpiry,
    );
    return KdpSubmissionRequest(
      depositId: depositId,
      title: publication.title,
      author: publication.author,
      description: publication.description,
      keywords: publication.keywords,
      categories: publication.categories,
      isbn: publication.isbn,
      language: publication.language,
      publisher: publication.publisher,
      epubUrl: epubUrl,
      pdfUrl: pdfUrl,
    );
  }

  /// Ouvre la tentative de dépôt.
  ///
  /// La trace est écrite avant l'appel à Amazon : un dépôt qui n'aboutit
  /// pas reste en attente, et il se réconcilie.
  ///
  /// Une reprise ne s'applique que si la trace est encore dans l'état
  /// qu'elle avait à la lecture : la comparaison est atomique, elle est
  /// faite par la base. Deux demandes concurrentes ne peuvent donc pas
  /// remettre le même dossier chez Amazon.
  Future<KdpDeposit> _startDeposit(
    KdpPublication publication,
    KdpDeposit? existing,
    String depositId,
  ) async {
    final DateTime now = _clock();
    final KdpDeposit started = existing == null
        ? KdpDeposit(
            id: depositId,
            publicationId: publication.id,
            userId: publication.userId,
            status: KdpDepositStatus.pending,
            issues: const <KdpIssue>[],
            attempts: 1,
            createdAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: KdpDepositStatus.pending,
            issues: const <KdpIssue>[],
            amazonSubmissionId: null,
            failureReason: null,
            attempts: existing.attempts + 1,
            updatedAt: now,
          );
    if (existing == null) {
      await deposits.insertDeposit(started);
      return started;
    }
    final bool applied = await deposits.updateDepositIfStatus(
      started,
      expectedStatus: existing.status,
    );
    if (!applied) {
      // La trace a changé entre-temps : une autre demande a repris ce
      // dossier. Elle l'a déjà remis à Amazon, celle-ci ne doit pas le
      // renvoyer.
      throw StateError(
        'The deposit ${existing.id} was resumed by another request.',
      );
    }
    return started;
  }

  /// Consigne le verdict d'Amazon.
  ///
  /// Un échec technique est consigné puis rendu comme une panne : le dépôt
  /// reste dans la trace et il est repris au tour suivant. Un dossier parti
  /// dont l'issue n'est pas connue est consigné comme tel : il n'est plus
  /// repris tout seul.
  Future<KdpDeposit> _record(
    KdpDeposit started,
    KdpSubmissionOutcome outcome,
  ) async {
    final DateTime now = _clock();
    switch (outcome) {
      case KdpSubmissionAccepted(:final String submissionId):
        final KdpDeposit deposit = started.copyWith(
          status: KdpDepositStatus.submitted,
          amazonSubmissionId: submissionId,
          issues: const <KdpIssue>[],
          failureReason: null,
          updatedAt: now,
        );
        await deposits.updateDeposit(deposit);
        return deposit;
      case KdpSubmissionRefused(:final List<KdpIssue> issues):
        final KdpDeposit deposit = started.copyWith(
          status: KdpDepositStatus.rejected,
          issues: issues,
          failureReason: null,
          updatedAt: now,
        );
        await deposits.updateDeposit(deposit);
        return deposit;
      case KdpSubmissionUnavailable(:final String reason):
        final KdpDeposit deposit = started.copyWith(
          status: KdpDepositStatus.failed,
          failureReason: reason,
          updatedAt: now,
        );
        await deposits.updateDeposit(deposit);
        throw ServiceUnavailableException(
          message: reason,
          details: <String, Object?>{
            'deposit_id': deposit.id,
            'status': deposit.status.key,
          },
        );
      case KdpSubmissionUnknown(:final String reason):
        final KdpDeposit deposit = started.copyWith(
          status: KdpDepositStatus.unknown,
          failureReason: reason,
          updatedAt: now,
        );
        await deposits.updateDeposit(deposit);
        throw _uncertainOutcome(deposit);
    }
  }

  /// Le dépôt [deposit] dont l'issue n'est pas connue, rendu à l'auteur.
  ConflictException _uncertainOutcome(KdpDeposit deposit) {
    return ConflictException(
      message: deposit.status == KdpDepositStatus.pending
          ? pendingOutcomeMessage
          : unknownOutcomeMessage,
      details: <String, Object?>{
        'deposit_id': deposit.id,
        'status': deposit.status.key,
        'failure_reason': deposit.failureReason,
        'requires_reconciliation': true,
      },
    );
  }

  /// Le dépôt [deposit] que l'auteur déclare avoir été enregistré par
  /// Amazon.
  ///
  /// L'identifiant de la soumission est borné : c'est le seul texte libre
  /// que la déclaration de l'auteur apporte à la trace.
  KdpDeposit _confirmed(KdpDeposit deposit, KdpReconciliation reconciliation) {
    final String? submissionId = reconciliation.amazonSubmissionId;
    if (submissionId == null || submissionId.trim().isEmpty) {
      throw const ValidationException(
        field: 'amazon_submission_id',
        message:
            "L'identifiant de la soumission Amazon est obligatoire quand "
            "l'auteur déclare que la soumission existe.",
      );
    }
    if (submissionId.trim().length > maxAmazonSubmissionIdLength) {
      throw ValidationException(
        field: 'amazon_submission_id',
        message:
            "L'identifiant de la soumission Amazon ne doit pas dépasser "
            '$maxAmazonSubmissionIdLength caractères.',
      );
    }
    return deposit.copyWith(
      status: KdpDepositStatus.submitted,
      amazonSubmissionId: submissionId.trim(),
      failureReason: null,
      updatedAt: _clock(),
    );
  }

  /// La longueur maximale de l'identifiant d'une soumission chez Amazon.
  static const int maxAmazonSubmissionIdLength = 256;
}

/// Le dossier a déjà été déposé et accepté pendant cette demande.
///
/// L'exception est interne au service : elle dit qu'une autre demande a
/// obtenu l'acceptation d'Amazon, et que celle-ci n'y renvoie rien.
final class _AlreadySubmitted implements Exception {
  /// Crée l'exception.
  const _AlreadySubmitted(this.deposit);

  /// Le dépôt qu'Amazon a accepté.
  final KdpDeposit deposit;
}
