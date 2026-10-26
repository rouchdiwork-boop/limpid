// Le domaine partagé porte un `ExportFormat` et un `CoverVariant` de son
// propre : ce sont ceux du moteur d'export qui font l'affaire ici, car
// c'est le moteur qui produit l'artefact.
import 'package:limpid_core/limpid_core.dart'
    hide CoverVariant, ExportFormat, ExportJobStatus;
import 'package:limpid_export/limpid_export.dart';

import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../db/export_job_record.dart';
import '../db/export_job_store.dart';
import '../db/kdp_database.dart';
import '../db/kdp_record.dart';
import '../db/project_record.dart';
import '../db/project_store.dart';
import '../db/quota_database.dart';
import '../db/sync_op_record.dart';
import '../db/sync_store.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../logging/logger.dart';
import '../storage/artifact_keys.dart';
import '../storage/object_storage.dart';
import '../sync/tree_builder.dart';
import 'book_builder.dart';
import 'plan_catalog.dart';
import 'quota_service.dart';
import 'storage_usage.dart';
import 'webhook_dispatcher.dart';
import 'webhook_service.dart';

/// La durée de vie de l'artefact d'un export.
///
/// L'artefact produit reste téléchargeable quinze minutes après la fin du
/// travail : au-delà, l'adresse qui le sert refuse de le rendre, et le
/// worker efface l'objet du stockage.
///
/// La durée est une **constante nommée** : elle ne s'écrit en dur nulle
/// part, et les testes la reprennent telle quelle.
const Duration exportArtifactLifetime = Duration(minutes: 15);

/// Le format d'export de nom technique [name], `null` quand il est
/// inconnu.
///
/// Le nom technique est le nom de l'énumération du moteur d'export : il
/// est stable, et il se relit sans connaître le contrat HTTP.
ExportFormat? exportFormatOfName(String name) {
  for (final ExportFormat format in ExportFormat.values) {
    if (format.name == name) return format;
  }
  return null;
}

/// La variante de couverture de nom technique [name].
///
/// Une variante inconnue est refusée : une couverture qui n'existe pas
/// n'est jamais quietly remplacée par une autre.
CoverVariant exportCoverOfName(String name) {
  final CoverVariant? variant = CoverVariant.tryParse(name);
  if (variant == null) {
    throw ValidationException(
      field: 'cover',
      message: 'La variante de couverture « $name » est inconnue.',
    );
  }
  return variant;
}

/// Le service des travaux d'export.
///
/// Le service porte la règle du travail : la demande crée un travail en
/// attente, la production fabrique l'artefact, la relance crée un travail
/// **neuf**. Un travail est un événement : il n'est jamais rejoué.
///
/// Le service ne rend **jamais** le fichier à l'appelant : il range
/// l'artefact dans le stockage et l'author rend par l'adresse signée que
/// la route de consultation lui donne.
final class ExportService {
  /// Crée un service.
  ///
  /// [clock] rend l'heure injectable : les tests font passer le temps sans
  /// attendre, et l'expiration de l'artefact se mesure ainsi.
  ExportService({
    required this.jobs,
    required this.projects,
    required this.sync,
    required this.storage,
    this.kdp,
    this.quota,
    this.audit,
    this.dispatcher,
    this.logger,
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow,
       _ids = UlidGenerator();

  /// La file des travaux.
  final ExportJobStore jobs;

  /// Les livres des comptes.
  final ProjectStore projects;

  /// Le journal de synchronisation des livres.
  final SyncStore sync;

  /// Le stockage des artefacts.
  final ObjectStorage storage;

  /// Les publications Amazon, quand la fonctionnalité est câblée.
  final KdpDatabase? kdp;

  /// Le garde-fou des quotas, `null` quand le service n'en a pas.
  final QuotaService? quota;

  /// Le journal d'audit, `null` quand le service n'en a pas.
  final AuditLog? audit;

  /// Le dispatcher des webhooks, `null` quand le service n'en a pas.
  final WebhookDispatcher? dispatcher;

  /// Le journal du serveur, `null` quand le service n'en a pas.
  ///
  /// Il ne reçoit que des identifiants et le type de l'erreur : ni le
  /// texte du livre, ni la trace d'exécution.
  final Logger? logger;

  /// Le service d'export du serveur.
  ///
  /// La file [jobs] est partagée par la route et par le worker : c'est
  /// elle qui porte les travaux en attente, et c'est elle qui permet à un
  /// serveur de reprendre les travaux d'un serveur arrêté.
  factory ExportService.forServer(
    AppDependencies dependencies, {
    required ExportJobStore jobs,
    DateTime Function()? clock,
  }) {
    final QuotaDatabase? quotas = dependencies.quotas;
    return ExportService(
      jobs: jobs,
      projects: dependencies.projects,
      sync: dependencies.sync,
      storage: dependencies.storage,
      kdp: dependencies.kdp,
      quota: quotas == null
          ? null
          : QuotaService(
              database: quotas,
              dispatcher: dependencies.webhookDispatcher,
            ),
      audit: dependencies.audit,
      dispatcher: dependencies.webhookDispatcher,
      logger: dependencies.logger,
      clock: clock,
    );
  }

  final DateTime Function() _clock;

  /// Le générateur des identifiants de travail.
  final UlidGenerator _ids;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// L'instant courant du service, en UTC.
  ///
  /// L'heure du service est la seule horloge du travail : c'est elle qui
  /// mesure l'expiration de l'artefact.
  DateTime get now => _clock().toUtc();

  /// Demande un export et rend le travail en attente.
  ///
  /// La demande vérifie le droit de l'auteur sur le livre et le quota
  /// d'exports **avant** de créer le travail : une demande refusée ne
  /// coûte rien au compte, et ne laisse aucun travail dans la file.
  ///
  /// Le travail rendu est en attente : l'artefact n'est pas produit ici.
  Future<ExportJobRecord> request({
    required String userId,
    required String projectId,
    required ExportFormat format,
    required CoverVariant cover,
  }) async {
    await _requireAccess(userId, projectId);

    // Le garde-fou du quota passe avant la création du travail : un
    // compte qui a épuisé son quota d'exports ne remplit pas la file.
    await quota?.ensureCounter(userId: userId, feature: QuotaFeature.exports);
    if (format == ExportFormat.pdfPrintReady) {
      await quota?.ensureCapability(
        userId: userId,
        capability: PlanCapability.printReadyExports,
      );
    }

    // Un livre sans contenu n'a rien à exporter : la demande est refusée
    // tout de suite, et l'auteur ne voit pas un travail qui ne peut pas
    // réussir.
    await _requireContent(projectId);

    final DateTime now = _clock().toUtc();
    final ExportJobRecord job = ExportJobRecord(
      id: _nextId(),
      userId: userId,
      projectId: projectId,
      format: format.name,
      cover: cover.name,
      status: ExportJobStatus.queued,
      createdAt: now,
    );
    await jobs.insert(job);
    await _announceRequest(job);
    return job;
  }

  /// Produit l'artefact du travail [job].
  ///
  /// La méthode rend le travail fini, qu'il ait réussi ou échoué : un
  /// travail qui reste en attente bloquerait la file.
  ///
  /// **L'échec ne consomme rien** : la consommation n'est comptée qu'après
  /// l'écriture de l'artefact.
  Future<ExportJobRecord> run(ExportJobRecord job) async {
    final DateTime startedAt = _clock().toUtc();
    final ExportJobRecord running = job.copyWith(
      status: ExportJobStatus.running,
      startedAt: startedAt,
    );
    await jobs.update(running);

    try {
      final ExportBook book = await _buildBook(running);
      final ExportResult result = await _export(running, book);

      // Le garde-fou du stockage passe avant l'écriture : un compte dont
      // le stockage est plein refuse l'artefact, et rien n'est écrit.
      await _ensureStorageFits(running.userId, result.bytes.length);

      final String key =
          '${ArtifactKeys.prefixOfProject(running.projectId)}'
          '${result.fileName}';
      await storage.put(
        key: key,
        bytes: result.bytes,
        contentType: result.mimeType,
      );

      // L'export a réussi : la consommation est comptée une fois, et une
      // seule.
      await quota?.recordConsumption(
        userId: running.userId,
        feature: QuotaFeature.exports,
      );

      final DateTime finishedAt = _clock().toUtc();
      final ExportJobRecord succeeded = running.copyWith(
        status: ExportJobStatus.succeeded,
        artifactKey: key,
        finishedAt: finishedAt,
        expiresAt: finishedAt.add(exportArtifactLifetime),
      );
      await jobs.update(succeeded);
      await _announceSuccess(succeeded, result);
      return succeeded;
    } on Object catch (error, stackTrace) {
      // Un travail qui reste « running » bloquerait la file : le worker le
      // prendrait pour un travail en cours. Tout échec — même une erreur
      // de programmation — termine donc le travail en « failed », et la
      // cause est journalisée.
      final ExportJobRecord failed = running.copyWith(
        status: ExportJobStatus.failed,
        error: _messageOf(error),
        errorCode: _codeOf(error),
        finishedAt: _clock().toUtc(),
      );
      await jobs.update(failed);
      await _announceFailure(failed, error, stackTrace);
      return failed;
    }
  }

  /// Crée un travail neuf à partir du travail en échec [failed].
  ///
  /// La relance ne ressuscite **jamais** l'ancien travail : un travail est
  /// un événement, pas un objet qu'on rejoue. Le travail neuf porte le même
  /// livre, le même format et la même couverture.
  Future<ExportJobRecord> retry(ExportJobRecord failed) async {
    final ExportFormat? format = exportFormatOfName(failed.format);
    if (format == null) {
      throw ValidationException(
        field: 'format',
        message:
            'Le format « ${failed.format} » du travail en échec est inconnu.',
      );
    }
    return request(
      userId: failed.userId,
      projectId: failed.projectId,
      format: format,
      cover: exportCoverOfName(failed.cover),
    );
  }

  /// Le travail [id], `null` quand il n'existe pas.
  Future<ExportJobRecord?> read(String id) => jobs.findById(id);

  /// Efface les artefacts dont la durée de vie est dépassée.
  ///
  /// L'artefact d'un export expire quinze minutes après la fin du travail :
  /// sans cet effacement, il occuperait le stockage du compte pour toujours,
  /// et la jauge du stockage le compterait alors que l'auteur ne peut plus
  /// le télécharger.
  ///
  /// La méthode rend le nombre d'artefacts effacés. Un stockage qui ne
  /// sait pas effacer n'efface rien : l'artefact reste, et l'adresse qui
  /// le sert refuse de le rendre.
  Future<int> discardExpired() async {
    final ObjectStorageDeletion? deletion = switch (storage) {
      final ObjectStorageDeletion capable => capable,
      _ => null,
    };
    if (deletion == null) return 0;

    final List<ExportJobRecord> expired = await jobs.listExpired(
      now: _clock().toUtc(),
    );
    var erased = 0;
    for (final ExportJobRecord job in expired) {
      final String? key = job.artifactKey;
      if (key == null) continue;
      await deletion.delete(key: key);
      erased++;
    }
    return erased;
  }

  /// Le livre et le rôle de l'auteur [userId] sur le livre [projectId].
  ///
  /// Un livre hors de la portée de l'auteur est rapporté comme absent :
  /// son existence n'est pas divulguée.
  Future<ProjectAccess> _requireAccess(String userId, String projectId) async {
    final ProjectAccess? access = await projects.access(
      projectId: projectId,
      userId: userId,
    );
    if (access == null) {
      throw const NotFoundException();
    }
    return access;
  }

  /// Refuse un livre qui n'a encore aucun contenu.
  Future<void> _requireContent(String projectId) async {
    final List<DocumentTree> trees = await _treesOf(projectId);
    final bool hasContent = trees.any(
      (DocumentTree tree) => tree.blocks.isNotEmpty,
    );
    if (hasContent) return;
    throw const ConflictException(
      message: "Ce projet n'a encore aucun contenu à exporter.",
    );
  }

  /// Les arbres des documents du livre [projectId].
  Future<List<DocumentTree>> _treesOf(String projectId) async {
    final List<SyncOpRecord> operations = await sync.all(projectId: projectId);
    return TreeBuilder.build(operations);
  }

  /// Construit le livre exporté.
  ///
  /// L'ISBN et l'auteur viennent de la fiche Amazon KDP du projet quand elle
  /// existe : l'édition imprimée porte alors son code-barres. Un livre sans
  /// fiche n'en porte pas : l'export n'invente jamais un ISBN.
  Future<ExportBook> _buildBook(ExportJobRecord job) async {
    final ProjectAccess access = await _requireAccess(
      job.userId,
      job.projectId,
    );
    final List<DocumentTree> trees = await _treesOf(job.projectId);
    final KdpPublication? publication = await kdp?.findPublicationByProject(
      projectId: job.projectId,
    );
    return BookBuilder.build(
      project: access.project,
      trees: trees,
      isbn: publication?.isbn,
      author: publication?.author,
    );
  }

  /// Fabrique l'artefact du travail [job].
  Future<ExportResult> _export(ExportJobRecord job, ExportBook book) async {
    final ExportFormat format = exportFormatOfName(job.format)!;
    final CoverVariant cover = exportCoverOfName(job.cover);
    try {
      // La couverture générée est attachée au livre avant l'export : les
      // formats qui l'embarquent (EPUB, ODT) la portent, ceux qui la nomment
      // (HTML, Markdown) la référencent.
      return await CoveredExporter(
        export: const LimpidExporter().export,
        variant: _variantOf(format, cover),
      ).call(format, book, const ExportOptions());
    } on ExportException catch (error) {
      throw ExportFailedException(
        message: "L'export n'a pas pu être généré. Réessayez dans un instant.",
        details: <String, Object?>{'format': format.name},
        cause: error,
      );
    }
  }

  /// La variante de couverture d'un format.
  ///
  /// La maquette complète ne vaut que pour le PDF : les autres formats
  /// portent la couverture de face, une couverture étroite et le dos
  /// n'y ont pas leur place.
  static CoverVariant _variantOf(ExportFormat format, CoverVariant cover) {
    final bool isPdf =
        format == ExportFormat.pdfReflowable ||
        format == ExportFormat.pdfPrintReady;
    return isPdf ? cover : CoverVariant.front;
  }

  /// Vérifie que le stockage du compte tient l'artefact à écrire.
  Future<void> _ensureStorageFits(String userId, int charge) async {
    final QuotaService? guard = quota;
    if (guard == null) return;
    final AccountStorageUsage usage = AccountStorageUsage(
      projects: projects,
      storage: storage,
    );
    await guard.ensureGaugeFits(
      userId: userId,
      feature: QuotaFeature.storageBytes,
      current: await usage.bytesOf(userId),
      charge: charge,
    );
  }

  /// Le message d'échec porté par le travail.
  ///
  /// Le message est celui de l'erreur de l'application : il dit ce qui a
  /// échoué, jamais la trace d'exécution.
  static String _messageOf(Object error) {
    if (error is AppException) return error.message;
    return "L'export n'a pas pu être produit.";
  }

  /// Le code technique de l'échec porté par le travail.
  ///
  /// Le code dit pourquoi le travail a échoué : un quota atteint, un
  /// livre sans contenu, un générateur en faute. Une erreur qui n'est pas
  /// une erreur de l'application n'a pas de code : elle est un défaut.
  static String _codeOf(Object error) {
    if (error is AppException) return error.code;
    return ErrorCodes.internalError;
  }

  /// L'identifiant du travail suivant.
  String _nextId() => _ids.generate().toString();

  /// Journalise la demande d'export.
  Future<void> _announceRequest(ExportJobRecord job) async {
    await audit?.record(
      AuditEntry(
        userId: job.userId,
        action: 'export.requested',
        targetType: 'project',
        targetId: job.projectId,
        metadata: <String, Object?>{'format': job.format, 'job_id': job.id},
      ),
    );
  }

  /// Journalise et diffuse la fin réussie du travail.
  Future<void> _announceSuccess(
    ExportJobRecord job,
    ExportResult result,
  ) async {
    await audit?.record(
      AuditEntry(
        userId: job.userId,
        action: 'export.completed',
        targetType: 'project',
        targetId: job.projectId,
        metadata: <String, Object?>{
          'format': job.format,
          'job_id': job.id,
          'bytes': result.bytes.length,
        },
      ),
    );
    // La charge porte le projet, le format et la taille : ni le texte du
    // livre, ni le secret du point de rappel.
    dispatcher?.emit(
      userId: job.userId,
      event: WebhookEvent.exportCompleted,
      data: <String, Object?>{
        'project_id': job.projectId,
        'format': job.format,
        'bytes': result.bytes.length,
      },
    );
  }

  /// Journalise l'échec du travail.
  Future<void> _announceFailure(
    ExportJobRecord job,
    Object error,
    StackTrace stackTrace,
  ) async {
    logger?.error('export.failed', <String, Object?>{
      'job_id': job.id,
      'project_id': job.projectId,
      'error': error.runtimeType.toString(),
      'stack': stackTrace.toString(),
    });
    await audit?.record(
      AuditEntry(
        userId: job.userId,
        action: 'export.failed',
        targetType: 'project',
        targetId: job.projectId,
        metadata: <String, Object?>{
          'format': job.format,
          'job_id': job.id,
          'error': error.runtimeType.toString(),
        },
      ),
    );
  }
}
