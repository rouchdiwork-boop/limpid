import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_import/limpid_import.dart';

import '../db/sync_op_record.dart';
import '../db/sync_store.dart';
import '../sync/sync_protocol.dart';

/// Le nombre de chiffres de l'index des cles de tri.
///
/// Les cles de tri sont des fractions decimales comparees comme des
/// chaines : leur longueur fixe garantit que deux cles d'un meme import
/// se comparent dans l'ordre de leur creation.
const int importOrderKeyDigits = 9;

/// La scene creee par un import.
final class ImportedSceneRecord {
  /// Cree une scene importee.
  const ImportedSceneRecord({
    required this.title,
    required this.blockCount,
    this.blockId,
  });

  /// Le titre de la scene.
  final String title;

  /// Le nombre de blocs de la scene.
  final int blockCount;

  /// L'identifiant du bloc qui porte le titre de la scene.
  ///
  /// Vaut `null` quand la scene n'a pas de titre : ses blocs sont alors
  /// les blocs racine du document.
  final String? blockId;

  /// La representation JSON envoyee aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'block_count': blockCount,
      'block_id': blockId,
    };
  }
}

/// Le chapitre cree par un import.
final class ImportedChapterRecord {
  /// Cree un chapitre importe.
  const ImportedChapterRecord({
    required this.documentId,
    required this.title,
    required this.level,
    required this.scenes,
    required this.blockCount,
  });

  /// L'identifiant du document CRDT qui porte le chapitre.
  final String documentId;

  /// Le titre du chapitre.
  final String title;

  /// Le niveau du titre du chapitre.
  final int level;

  /// Les scenes du chapitre, dans l'ordre de lecture.
  final List<ImportedSceneRecord> scenes;

  /// Le nombre de blocs du chapitre.
  final int blockCount;

  /// La representation JSON envoyee aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'document_id': documentId,
      'title': title,
      'level': level,
      'scene_count': scenes.length,
      'block_count': blockCount,
      'scenes': scenes
          .map((ImportedSceneRecord scene) => scene.toJson())
          .toList(),
    };
  }
}

/// Le resultat d'un import de manuscrit.
final class ManuscriptImportResult {
  /// Cree un resultat d'import.
  const ManuscriptImportResult({
    required this.format,
    required this.title,
    required this.chapters,
    required this.skipped,
    required this.blockCount,
    required this.wordCount,
  });

  /// Le format du fichier importe.
  final ImportFormat format;

  /// Le titre du manuscrit importe.
  final String title;

  /// Les chapitres crees, dans l'ordre de lecture.
  final List<ImportedChapterRecord> chapters;

  /// Les contenus que l'import a laisses de cote.
  final List<ImportSkip> skipped;

  /// Le nombre total de blocs crees.
  final int blockCount;

  /// Le nombre total de mots importes.
  final int wordCount;

  /// Le nombre de chapitres crees.
  int get chapterCount => chapters.length;

  /// Le nombre de scenes creees.
  int get sceneCount => chapters.fold<int>(
    0,
    (int total, ImportedChapterRecord chapter) => total + chapter.scenes.length,
  );

  /// La representation JSON envoyee aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'format': format.name,
      'title': title,
      'chapter_count': chapterCount,
      'scene_count': sceneCount,
      'block_count': blockCount,
      'word_count': wordCount,
      'chapters': chapters
          .map((ImportedChapterRecord chapter) => chapter.toJson())
          .toList(),
      'skipped': skipped
          .map(
            (ImportSkip skip) => <String, Object?>{
              'reason': skip.reason,
              'count': skip.count,
            },
          )
          .toList(),
    };
  }
}

/// L'import d'un manuscrit dans un projet.
///
/// L'import ecrit dans le **journal de synchronisation** : c'est le seul
/// endroit ou le texte d'un manuscrit vit sur le serveur, et c'est celui que
/// l'export relit. Un import n'ecrase rien : il ajoute des documents, et la
/// suppression d'un chapitre importe passe par la route de suppression
/// habituelle.
///
/// Chaque chapitre devient un document CRDT : le titre du chapitre est
/// porte par les metadonnees du document, et chaque scene devient un bloc
/// de titre dont les blocs sont les enfants. La structure reste donc
///modifiable apres l'import.
final class ManuscriptImportService {
  /// Cree un service d'import.
  ///
  /// [importer] permet d'injecter un autre moteur d'import.
  ManuscriptImportService({required this.sync, ManuscriptImporter? importer})
    : _importer = importer ?? const LimpidImporter();

  /// Le journal de synchronisation ou les documents importes sont ecrits.
  final SyncStore sync;

  final ManuscriptImporter _importer;

  /// Importe le manuscrit de [request] dans le projet [projectId].
  ///
  /// Leve une [ImportException] quand le format est inconnu ou quand le
  /// fichier est illisible.
  Future<ManuscriptImportResult> import({
    required String projectId,
    required String authorId,
    required ImportRequest request,
  }) async {
    final ImportFormat format = _detect(request);
    final ImportedManuscript manuscript = await _importer.import(request);
    if (manuscript.chapterCount == 0) {
      throw const ImportException(
        ImportErrorCodes.empty,
        'Le fichier ne contient aucun texte importable.',
      );
    }
    final _ImportWriter writer = _ImportWriter(
      projectId: projectId,
      authorId: authorId,
    );
    final List<ImportedChapterRecord> chapters = writer.write(manuscript);

    await sync.append(projectId: projectId, operations: writer.operations);

    return ManuscriptImportResult(
      format: format,
      title: manuscript.title,
      chapters: chapters,
      skipped: manuscript.skipped,
      blockCount: manuscript.blockCount,
      wordCount: manuscript.wordCount,
    );
  }

  /// Le format du fichier, refuse quand il n'est pas reconnu.
  ImportFormat _detect(ImportRequest request) {
    final ImportFormat? detected = ImportFormatDetector.detect(request);
    if (detected == null) {
      throw const ImportException(
        ImportErrorCodes.unsupportedFormat,
        "Le format du fichier n'est pas reconnu. Formats acceptes : "
        'docx, odt, epub, rtf, md, txt.',
      );
    }
    return detected;
  }
}

/// L'ecriture des operations de synchronisation d'un import.
///
/// Le redacteur tient le compte desoperations, des cles de tri et des
/// identifiants : il produit une liste d'operations pretes a etre ecrites
/// dans le journal.
final class _ImportWriter {
  _ImportWriter({required this.projectId, required this.authorId});

  /// Le projet qui recoit l'import.
  final String projectId;

  /// L'auteur de l'import.
  final String authorId;

  final List<SyncOpRecord> _operations = <SyncOpRecord>[];
  final UlidGenerator _ids = UlidGenerator();
  var _lamport = 0;
  var _order = 0;

  /// Les operations ecrites jusqu'ici.
  List<SyncOpRecord> get operations =>
      List<SyncOpRecord>.unmodifiable(_operations);

  /// Ecrit les chapitres de [manuscript] et rend ce qui a ete cree.
  List<ImportedChapterRecord> write(ImportedManuscript manuscript) {
    final List<ImportedChapterRecord> chapters = <ImportedChapterRecord>[];
    for (final ImportedChapter chapter in manuscript.chapters) {
      chapters.add(_writeChapter(chapter));
    }
    return chapters;
  }

  ImportedChapterRecord _writeChapter(ImportedChapter chapter) {
    final String documentId = _ids.generate().value;
    final int sceneLevel = chapter.level >= 3 ? 3 : chapter.level + 1;

    _writeMeta(documentId, 'title', chapter.title);
    _writeMeta(documentId, 'level', '${chapter.level}');

    final List<ImportedSceneRecord> scenes = <ImportedSceneRecord>[];
    var blockCount = 0;
    for (final ImportedScene scene in chapter.scenes) {
      final String? sceneBlockId = scene.title.isEmpty
          ? null
          : _writeBlock(
              documentId: documentId,
              parentId: null,
              type: _blockTypeOfHeading(sceneLevel),
              content: scene.title,
            );
      for (final ImportedBlock block in scene.blocks) {
        _writeBlock(
          documentId: documentId,
          parentId: sceneBlockId,
          type: _blockTypeOf(block.type),
          content: block.text,
        );
      }
      blockCount += scene.blocks.length;
      scenes.add(
        ImportedSceneRecord(
          title: scene.title,
          blockCount: scene.blocks.length,
          blockId: sceneBlockId,
        ),
      );
    }

    return ImportedChapterRecord(
      documentId: documentId,
      title: chapter.title,
      level: chapter.level,
      scenes: List<ImportedSceneRecord>.unmodifiable(scenes),
      blockCount: blockCount,
    );
  }

  void _writeMeta(String documentId, String key, String value) {
    _operations.add(
      SyncOpRecord(
        opId: _ids.generate().value,
        projectId: projectId,
        docId: documentId,
        lamport: ++_lamport,
        authorId: authorId,
        type: 'setMeta',
        payload: <String, dynamic>{'key': key, 'value': value},
        schemaVersion: syncSchemaVersion,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  String _writeBlock({
    required String documentId,
    required String? parentId,
    required String type,
    required String content,
  }) {
    final String blockId = _ids.generate().value;
    _operations.add(
      SyncOpRecord(
        opId: _ids.generate().value,
        projectId: projectId,
        docId: documentId,
        lamport: ++_lamport,
        authorId: authorId,
        type: 'insertBlock',
        payload: <String, dynamic>{
          'block_id': blockId,
          'parent_id': parentId,
          'order_key': _nextOrderKey(),
          'type': type,
          'content': content,
        },
        schemaVersion: syncSchemaVersion,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    return blockId;
  }

  /// La cle de tri du prochain bloc.
  ///
  /// La cle est une fraction decimale de longueur fixe : deux blocs
  /// importes se comparent donc dans l'ordre de leur creation, quel que
  /// soit le nombre de blocs du document.
  String _nextOrderKey() {
    _order++;
    return '5${_order.toString().padLeft(importOrderKeyDigits, '0')}1';
  }

  static String _blockTypeOf(ImportedBlockType type) => switch (type) {
    ImportedBlockType.paragraph => 'paragraph',
    ImportedBlockType.listItem => 'listItem',
    ImportedBlockType.quote => 'quote',
    ImportedBlockType.code => 'code',
  };

  static String _blockTypeOfHeading(int level) => switch (level) {
    1 => 'heading1',
    2 => 'heading2',
    _ => 'heading3',
  };
}
