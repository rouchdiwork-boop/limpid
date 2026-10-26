import 'package:limpid_core/limpid_core.dart';

import '../db/project_record.dart';
import '../db/project_store.dart';
import '../db/sync_op_record.dart';
import '../db/sync_store.dart';
import '../errors/app_exception.dart';
import '../http/pagination.dart';
import '../sync/tree_builder.dart';

/// La métadonnée qui porte le titre d'une scène.
const String _sceneTitleMeta = 'title';

/// La métadonnée qui porte le chapitre d'une scène.
const String _chapterIdMeta = 'chapter_id';

/// La métadonnée qui porte le titre du chapitre d'une scène.
const String _chapterTitleMeta = 'chapter_title';

/// Une scène d'un projet, vue par l'API publique.
///
/// La scène est l'unité atomique du manuscrit (D-02) : elle porte un
/// document synchronisé. L'API publique en donne la structure — le titre, le
/// nombre de mots, le nombre de blocs — jamais le texte : le texte se lit
/// par la route de l'arbre.
final class PublicScene {
  /// Crée une scène.
  const PublicScene({
    required this.docId,
    required this.title,
    required this.wordCount,
    required this.blockCount,
    required this.lamport,
  });

  /// L'identifiant du document synchronisé de la scène.
  final String docId;

  /// Le titre de la scène.
  final String title;

  /// Le nombre de mots écrits dans la scène.
  final int wordCount;

  /// Le nombre de blocs vivants de la scène.
  final int blockCount;

  /// L'horloge logique du document de la scène.
  final int lamport;

  /// La représentation JSON envoyée aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'doc_id': docId,
      'title': title,
      'word_count': wordCount,
      'block_count': blockCount,
      'lamport': lamport,
    };
  }
}

/// Un chapitre d'un projet, vu par l'API publique.
///
/// Le chapitre est une vue sur les scènes (D-02) : il ne porte aucun texte,
/// seulement l'ordre de ses scènes. Une scène qui ne déclare aucun chapitre
/// forme un chapitre à elle seule.
final class PublicChapter {
  /// Crée un chapitre.
  const PublicChapter({
    required this.id,
    required this.title,
    required this.order,
    required this.scenes,
  });

  /// L'identifiant du chapitre.
  final String id;

  /// Le titre du chapitre.
  final String title;

  /// L'ordre du chapitre dans le projet.
  final int order;

  /// Les scènes du chapitre, dans l'ordre de lecture.
  final List<PublicScene> scenes;

  /// La représentation JSON envoyée aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'order': order,
      'scenes': scenes
          .map((PublicScene scene) => scene.toJson())
          .toList(growable: false),
    };
  }
}

/// Un projet et sa structure, vus par l'API publique.
final class PublicProject {
  /// Crée une vue de projet.
  const PublicProject({required this.project, required this.chapters});

  /// Le projet.
  final ProjectRecord project;

  /// Les chapitres du projet.
  final List<PublicChapter> chapters;
}

/// La lecture des ressources du compte pour l'API publique.
///
/// Le service n'authentifie personne : il lit le compte que la clé d'API a
/// désigné et ne renvoie que ses projets. Un projet qui n'appartient pas à
/// ce compte est traité comme absent : son existence n'est jamais divulguée.
final class PublicApiService {
  /// Crée un service sur les ports [projects] et [sync].
  const PublicApiService({required this.projects, required this.sync});

  /// Le port des projets.
  final ProjectStore projects;

  /// Le port du journal de synchronisation.
  final SyncStore sync;

  /// La page des projets écrits par [userId].
  ///
  /// La liste ne porte que les projets dont [userId] est l'auteur : un
  /// projet partagé avec un autre compte appartient à cet autre compte,
  /// l'API publique ne le divulgue pas.
  Future<ProjectPage> listProjects({
    required String userId,
    required int limit,
    required String? cursor,
  }) async {
    final List<ProjectRecord> owned =
        (await projects.listAll(userId: userId))
            .where(
              (ProjectRecord record) =>
                  record.ownerId == userId && !record.isDeleted,
            )
            .toList(growable: false)
          ..sort(_byUpdate);

    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final DateTime? pivot = decoded == null
        ? null
        : DateTime.tryParse(decoded.updatedAt);
    final List<ProjectRecord> after = decoded == null || pivot == null
        ? owned
        : owned
              .where(
                (ProjectRecord record) => _isAfter(record, pivot, decoded.id),
              )
              .toList(growable: false);

    final List<ProjectRecord> items = after.take(limit).toList(growable: false);
    final bool hasMore = after.length > items.length;
    final String? nextCursor = hasMore && items.isNotEmpty
        ? PageCursor.encode(
            items.last.updatedAt.toUtc().toIso8601String(),
            items.last.id,
          )
        : null;
    return ProjectPage(
      items: items,
      total: owned.length,
      nextCursor: nextCursor,
    );
  }

  /// Le projet [projectId] et sa structure, pour le compte [userId].
  ///
  /// Lève une [NotFoundException] quand le projet n'appartient pas à
  /// [userId] : un projet d'un autre compte est absent, jamais interdit.
  Future<PublicProject> describe({
    required String userId,
    required String projectId,
  }) async {
    final ProjectRecord project = await _requireOwned(userId, projectId);
    final List<DocumentTree> trees = await _treesOf(projectId);
    return PublicProject(project: project, chapters: _chaptersOf(trees));
  }

  /// L'arbre du projet [projectId], pour le compte [userId].
  ///
  /// L'arbre a la forme de la synchronisation : c'est la même liste de
  /// documents que celle que la route `/v1/projects/:id/tree` renvoie.
  Future<List<DocumentTree>> tree({
    required String userId,
    required String projectId,
  }) async {
    await _requireOwned(userId, projectId);
    return _treesOf(projectId);
  }

  /// Le projet [projectId], s'il appartient à [userId].
  ///
  /// Un projet qui n'existe pas, qui est supprimé ou qui appartient à un
  /// autre compte reçoit le même refus : l'appelant ne peut pas deviner
  /// quels projets existent.
  Future<ProjectRecord> _requireOwned(String userId, String projectId) async {
    final ProjectAccess? access = await projects.access(
      projectId: projectId,
      userId: userId,
    );
    if (access == null) throw const NotFoundException();
    if (access.project.ownerId != userId) throw const NotFoundException();
    return access.project;
  }

  /// Les arbres des documents du projet [projectId].
  Future<List<DocumentTree>> _treesOf(String projectId) async {
    final List<SyncOpRecord> operations = await sync.all(projectId: projectId);
    return TreeBuilder.build(operations);
  }

  /// Les chapitres et les scènes des documents [trees].
  ///
  /// Une scène est un document synchronisé. Le chapitre d'une scène vient de
  /// ses métadonnées : une scène qui déclare un chapitre le rejoint, une
  /// scène qui n'en déclare pas forme un chapitre à elle seule.
  List<PublicChapter> _chaptersOf(List<DocumentTree> trees) {
    final List<PublicScene> scenes = <PublicScene>[];
    final List<String> chapterIds = <String>[];
    final List<String> chapterTitles = <String>[];

    for (int index = 0; index < trees.length; index++) {
      final DocumentTree tree = trees[index];
      final String title = _sceneTitleOf(tree, index);
      scenes.add(
        PublicScene(
          docId: tree.docId,
          title: title,
          wordCount: _wordCountOf(tree.blocks),
          blockCount: _blockCountOf(tree.blocks),
          lamport: tree.lamport,
        ),
      );
      chapterIds.add(_chapterIdOf(tree));
      chapterTitles.add(_chapterTitleOf(tree, title));
    }

    final List<String> order = <String>[];
    final Map<String, List<PublicScene>> grouped =
        <String, List<PublicScene>>{};
    final Map<String, String> titles = <String, String>{};
    for (int index = 0; index < scenes.length; index++) {
      final String id = chapterIds[index];
      final List<PublicScene>? known = grouped[id];
      if (known == null) {
        grouped[id] = <PublicScene>[scenes[index]];
        titles[id] = chapterTitles[index];
        order.add(id);
        continue;
      }
      known.add(scenes[index]);
    }

    return <PublicChapter>[
      for (int index = 0; index < order.length; index++)
        PublicChapter(
          id: order[index],
          title: titles[order[index]]!,
          order: index,
          scenes: grouped[order[index]]!,
        ),
    ];
  }

  /// Le titre de la scène portée par [tree].
  String _sceneTitleOf(DocumentTree tree, int index) {
    final String declared = tree.meta[_sceneTitleMeta]?.trim() ?? '';
    if (declared.isNotEmpty) return declared;
    return 'Scène ${index + 1}';
  }

  /// L'identifiant du chapitre de la scène portée par [tree].
  String _chapterIdOf(DocumentTree tree) {
    final String declared = tree.meta[_chapterIdMeta]?.trim() ?? '';
    if (declared.isNotEmpty) return declared;
    return tree.docId;
  }

  /// Le titre du chapitre de la scène portée par [tree].
  String _chapterTitleOf(DocumentTree tree, String sceneTitle) {
    final String declared = tree.meta[_chapterTitleMeta]?.trim() ?? '';
    if (declared.isNotEmpty) return declared;
    final String id = tree.meta[_chapterIdMeta]?.trim() ?? '';
    if (id.isNotEmpty) return id;
    return sceneTitle;
  }

  /// Le nombre de mots des blocs vivants de [blocks].
  int _wordCountOf(List<BlockNode> blocks) {
    var total = 0;
    for (final BlockNode block in blocks) {
      if (!block.deleted) total += WordCount.ofText(block.content);
      total += _wordCountOf(block.children);
    }
    return total;
  }

  /// Le nombre de blocs vivants de [blocks].
  int _blockCountOf(List<BlockNode> blocks) {
    var total = 0;
    for (final BlockNode block in blocks) {
      if (!block.deleted) total += 1;
      total += _blockCountOf(block.children);
    }
    return total;
  }

  /// L'ordre de la bibliothèque : le projet le plus récent d'abord.
  static int _byUpdate(ProjectRecord left, ProjectRecord right) {
    final int byDate = right.updatedAt.compareTo(left.updatedAt);
    if (byDate != 0) return byDate;
    return left.id.compareTo(right.id);
  }

  /// Indique si [record] se trouve après le curseur [pivot], [id].
  static bool _isAfter(ProjectRecord record, DateTime pivot, String id) {
    final int byDate = pivot.compareTo(record.updatedAt);
    if (byDate != 0) return byDate > 0;
    return record.id.compareTo(id) > 0;
  }
}
