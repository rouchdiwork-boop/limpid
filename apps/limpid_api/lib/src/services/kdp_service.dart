import 'package:limpid_core/limpid_core.dart' hide ExportFormat;
import 'package:limpid_export/limpid_export.dart';

import '../auth/auth_context.dart';
import '../db/kdp_database.dart';
import '../db/kdp_record.dart';
import '../db/project_record.dart';
import '../db/sync_op_record.dart';
import '../errors/app_exception.dart';
import '../storage/artifact_keys.dart';
import '../sync/tree_builder.dart';
import 'access_control.dart';
import 'book_builder.dart';
import 'kdp_metadata.dart';
import 'kdp_submission.dart';
import 'plan_catalog.dart';

/// Le service de publication Amazon KDP.
///
/// Le service reconstruit le livre, produit le fichier EPUB et le PDF
/// d'impression, contrôle le dossier et enregistre la trace de ce qui a
/// été préparé. Le fichier produit ne transite jamais dans une réponse :
/// la publication renvoie un lien de téléchargement.
///
/// Un projet ne porte qu'une fiche : préparer deux fois le même livre
/// rafraîchit la fiche, il n'en crée pas une seconde. L'identifiant de la
/// fiche est donc stable, et le dépôt — qui est dédoublonné par
/// `publication_id` — ne part pas deux fois chez Amazon.
final class KdpService {
  /// Crée un service.
  ///
  /// [clock] rend l'heure injectable : les tests font passer le temps sans
  /// attendre.
  KdpService({required this.database, DateTime Function()? clock})
    : _clock = clock ?? _utcNow;

  /// La base de la publication.
  final KdpDatabase database;

  /// L'heure courante, en UTC.
  final DateTime Function() _clock;

  /// La durée de validité des liens de téléchargement.
  static const Duration downloadExpiry = Duration(hours: 1);

  static final UlidGenerator _ulid = UlidGenerator();

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Prépare la publication d'un livre pour Amazon KDP.
  ///
  /// La publication est préparée même quand le contrôle relève un
  /// problème : l'auteur reçoit alors le dossier et la liste de ce qu'il
  /// doit corriger.
  ///
  /// Préparer deux fois le même livre rafraîchit la fiche du projet : il
  /// n'en crée pas une seconde, et l'identifiant de la fiche reste le
  /// sien.
  ///
  /// Un ISBN déjà porté par une autre fiche est refusé : le message nomme
  /// le conflit, l'auteur n'a pas à deviner de quel livre il s'agit.
  Future<KdpPublication> prepare({
    required AuthContext auth,
    required String projectId,
    required KdpMetadata metadata,
  }) async {
    await _ensurePlan(auth.userId);

    final ProjectAccess access = await AccessControl.requireProject(
      database.projects,
      projectId,
      auth,
    );

    final KdpPublication? existing = await database.findPublicationByProject(
      projectId: projectId,
    );
    await _requireFreeIsbn(metadata.isbn, existing);

    final List<SyncOpRecord> operations = await database.sync.all(
      projectId: projectId,
    );
    final List<DocumentTree> trees = TreeBuilder.build(operations);
    if (trees.isEmpty) {
      throw const ConflictException(
        message: "Ce projet n'a encore aucun contenu à publier.",
      );
    }

    final ExportBook book = _published(
      BookBuilder.build(
        project: access.project,
        trees: trees,
        isbn: metadata.isbn,
        author: metadata.author,
      ),
      metadata,
      access.project,
    );

    final ExportResult epub = await _export(
      ExportFormat.epub3,
      book,
      const ExportOptions(),
    );
    final ExportResult pdf = await _export(
      ExportFormat.pdfPrintReady,
      book,
      kdpPrintOptions,
    );

    final KdpSubmissionReport report = const KdpSubmissionCheck().check(
      metadata: metadata,
      book: book,
      epubBytes: epub.bytes,
      pdfBytes: pdf.bytes,
      printOptions: kdpPrintOptions,
    );

    // L'identifiant de la fiche est stable : la seconde préparation
    // reprend celui de la première, elle n'en fabrique pas un nouveau.
    final String publicationId = existing?.id ?? _ulid.generate().value;
    // Les fichiers sont écrits sous le préfixe du projet : c'est la
    // convention qui relie un compte à ses artefacts, et elle garantit que
    // la purge du compte les efface avec les autres.
    final String baseKey =
        '${ArtifactKeys.prefixOfProject(projectId)}kdp/$publicationId';
    final String epubKey = '$baseKey/${epub.fileName}';
    final String pdfKey = '$baseKey/${pdf.fileName}';

    await database.artefacts.put(
      key: epubKey,
      bytes: epub.bytes,
      contentType: epub.mimeType,
    );
    await database.artefacts.put(
      key: pdfKey,
      bytes: pdf.bytes,
      contentType: pdf.mimeType,
    );

    final KdpPublication publication = KdpPublication(
      id: publicationId,
      projectId: projectId,
      userId: auth.userId,
      title: metadata.title,
      author: metadata.author,
      description: metadata.description,
      keywords: metadata.keywords,
      categories: metadata.categories,
      issues: report.issues,
      isbn: metadata.isbn,
      language: metadata.language ?? access.project.language,
      publisher: metadata.publisher,
      status: report.isReady
          ? KdpPublicationStatus.ready
          : KdpPublicationStatus.blocked,
      wordCount: report.wordCount,
      pageCount: report.pageCount,
      epubKey: epubKey,
      pdfKey: pdfKey,
      epubBytes: epub.bytes.length,
      pdfBytes: pdf.bytes.length,
      manuscriptVersion: access.project.updatedAt.toUtc().toIso8601String(),
      createdAt: _clock(),
    );

    try {
      return await database.recordPublication(publication);
    } on Object {
      // L'index unique de l'ISBN peut refuser l'ecriture : c'est la base
      // qui tranche quand deux preparations concurrentes passent entre le
      // controle du service et l'ecriture. Le controle est refait ici — si
      // l'ISBN est desormais porte par une autre fiche, c'est un conflit
      // d'ISBN, pas une panne ; sinon l'echec remonte tel quel.
      await _requireFreeIsbn(metadata.isbn, existing);
      rethrow;
    }
  }

  /// Les publications du compte, les plus récentes d'abord.
  ///
  /// Quand [projectId] est donné, l'appelant doit avoir accès au projet :
  /// un projet hors de sa portée ne laisse rien deviner.
  Future<List<KdpPublication>> list({
    required AuthContext auth,
    String? projectId,
  }) async {
    if (projectId != null) {
      await AccessControl.requireProject(database.projects, projectId, auth);
    }
    return database.listPublications(userId: auth.userId, projectId: projectId);
  }

  /// La publication [publicationId] du compte, `null` quand elle n'existe
  /// pas.
  Future<KdpPublication?> find({
    required AuthContext auth,
    required String publicationId,
  }) {
    return database.findPublication(
      publicationId: publicationId,
      userId: auth.userId,
    );
  }

  /// La représentation JSON d'une publication, liens de téléchargement
  /// compris.
  ///
  /// Les liens sont signés et expirent : la trace ne les porte pas.
  Future<Map<String, Object?>> describe(KdpPublication publication) async {
    return <String, Object?>{
      ...publication.toJson(),
      'artefacts': <String, Object?>{
        'epub': <String, Object?>{
          'key': publication.epubKey,
          'size_in_bytes': publication.epubBytes,
          'download_url': await _downloadUrl(publication.epubKey),
        },
        'pdf': <String, Object?>{
          'key': publication.pdfKey,
          'size_in_bytes': publication.pdfBytes,
          'download_url': await _downloadUrl(publication.pdfKey),
        },
      },
    };
  }

  /// Applique les métadonnées de l'appelant au livre reconstruit.
  ///
  /// L'ISBN et l'auteur ont été posés par [BookBuilder] : ils sont
  /// conservés tels quels, l'export porte l'identité de l'ouvrage imprimé.
  ExportBook _published(
    ExportBook book,
    KdpMetadata metadata,
    ProjectRecord project,
  ) {
    final String language = metadata.language ?? project.language;
    return book.copyWith(
      title: metadata.title,
      language: language,
      metadata: ExportMetadata(
        isbn: book.metadata.isbn,
        description: metadata.description.isEmpty ? null : metadata.description,
        publisher: metadata.publisher,
        subjects: metadata.categories,
        language: language,
        identifier: project.id,
      ),
    );
  }

  /// Refuse un ISBN déjà porté par une autre fiche.
  ///
  /// L'ISBN identifie un ouvrage imprimé : deux fiches qui le portent
  /// désignent le même livre. La préparation est refusée et le message
  /// nomme l'ISBN en conflit. La fiche du projet lui-même peut reprendre
  /// son propre ISBN : c'est la même fiche qui est rafraîchie.
  Future<void> _requireFreeIsbn(String? isbn, KdpPublication? existing) async {
    if (isbn == null || isbn.trim().isEmpty) return;
    final KdpPublication? holder = await database.findPublicationByIsbn(
      isbn: isbn,
    );
    if (holder == null) return;
    if (existing != null && holder.id == existing.id) return;
    throw ConflictException(
      message:
          "L'ISBN $isbn est déjà utilisé par une autre fiche Amazon KDP : "
          "un ISBN ne désigne qu'un ouvrage imprimé.",
      details: <String, Object?>{'isbn': isbn, 'publication_id': holder.id},
    );
  }

  /// Produit un fichier de publication.
  Future<ExportResult> _export(
    ExportFormat format,
    ExportBook book,
    ExportOptions options,
  ) async {
    try {
      return await CoveredExporter(
        export: const LimpidExporter().export,
      ).call(format, book, options);
    } on ExportException catch (error) {
      throw ExportFailedException(
        message:
            "La publication Amazon KDP n'a pas pu être produite. Réessayez "
            'dans un instant.',
        details: <String, Object?>{'format': format.name},
        cause: error,
      );
    }
  }

  /// Vérifie que la formule du compte ouvre la publication Amazon.
  Future<void> _ensurePlan(String userId) async {
    final SubscriptionPlan? plan = _planOf(await database.planLookup(userId));
    if (plan != null &&
        PlanCatalog.hasCapability(plan, PlanCapability.printReadyExports)) {
      return;
    }
    final SubscriptionPlan required = PlanCatalog.minimumTierFor(
      PlanCapability.printReadyExports,
    );
    final SubscriptionPlan effective = plan ?? SubscriptionPlan.free;
    throw PlanLimitException(
      message:
          "La publication Amazon KDP n'est pas incluse dans la formule "
          '${PlanCatalog.definitionOf(effective).displayName}. Passez à la '
          'formule ${PlanCatalog.definitionOf(required).displayName} pour '
          'y accéder.',
      details: <String, Object?>{
        'feature': 'kdp_publication',
        'plan': effective.name,
        'required_plan': required.name,
      },
    );
  }

  /// Le lien de téléchargement temporaire d'un artefact.
  Future<String> _downloadUrl(String key) {
    return database.artefacts.presignedUrl(key: key, expires: downloadExpiry);
  }

  /// La formule nommée [name], `null` quand elle est inconnue.
  static SubscriptionPlan? _planOf(String? name) {
    if (name == null) return null;
    for (final SubscriptionPlan plan in SubscriptionPlan.values) {
      if (plan.name == name) return plan;
    }
    return null;
  }
}
