import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../db/project_record.dart';
import '../db/sync_op_record.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../middleware/rate_limiter.dart';
import '../sync/sync_protocol.dart';
import 'publication_author_routes.dart';

/// The route of the public page of a book.
const String publicBookRoute = '/v1/public/books/<projectId>';

/// The prefix of the public routes of the showcase.
const String publicBookRoutePrefix = '/v1/public/';

/// The number of public pages a single IP may burst.
const int publicBookRateLimitCapacity = 60;

/// How many public pages an IP regains per second.
const double publicBookRateLimitRefillPerSecond = 2;

/// The largest number of characters an excerpt keeps.
///
/// The value is the one of the application
/// (`apps/limpid_app/lib/src/domain/publication_repository.dart`): the page
/// of the server and the page of the device show the very same excerpt.
const int maxExcerptLength = 320;

/// The character appended to a truncated excerpt.
const String excerptEllipsis = '…';

/// Registers the routes of the public showcase.
///
/// The showcase is the **public catalogue** of the published books: its
/// route carries no token, and it answers the same `404` for a book that
/// does not exist, for a book that is not published and for a book that is
/// not public. A visitor must never learn that a private book exists.
///
/// The route is rate limited like the other routes: it is the only route a
/// stranger may call, and it reads the database of every call.
void registerPublicationRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config,
) {
  final TokenBucketRateLimiter limiter = TokenBucketRateLimiter(
    capacity: publicBookRateLimitCapacity,
    refillPerSecond: publicBookRateLimitRefillPerSecond,
  );
  final Middleware limit = rateLimitMiddleware(
    limiter: limiter,
    scope: 'public_book',
    applies: (Request request) =>
        request.requestedUri.path.startsWith(publicBookRoutePrefix),
  );

  router.get(publicBookRoute, (Request request, String projectId) {
    return limit((Request request) => _serveBook(dependencies, projectId))(
      request,
    );
  });

  // La page d'un auteur appartient à la même vitrine : elle est enregistrée
  // ici, parce que le routeur de l'API ne connaît que cette fonction.
  registerPublicationAuthorRoutes(router, dependencies, config);
}

/// Serves the public page of a book.
///
/// The publication predicate is applied **before** the manuscript is read:
/// the database refuses a project that is not published and public, and the
/// journal of a private book is never loaded. The slowest path of the route
/// therefore never depends on the content of a private book.
Future<Response> _serveBook(
  AppDependencies dependencies,
  String projectId,
) async {
  final ProjectRecord? project = await dependencies.projects.findPublic(
    projectId: projectId,
  );
  if (project == null) {
    // The three refusals — unknown book, unpublished book, private book —
    // answer the very same 404: the showcase must never disclose the
    // existence of a book the visitor may not read.
    throw const NotFoundException();
  }

  final List<SyncOpRecord> operations = await dependencies.sync.all(
    projectId: projectId,
  );
  final List<PublishedScene> scenes = _scenesOf(operations);
  return ApiResponse.ok(<String, Object?>{
    'project': _projectJson(project),
    'chapters': <Map<String, Object?>>[_chapterJson(project, scenes)],
    'wordCount': _totalWords(scenes),
  });
}

/// Le nombre de mots que le livre tient.
///
/// Le compte est lu dans le journal du livre, exactement comme la vitrine
/// d'un livre compte les mots de ses scènes : la page d'un auteur et la
/// vitrine d'un livre disent la même chose sur la longueur d'un manuscrit.
Future<int> publicWordCountOf(
  AppDependencies dependencies,
  String projectId,
) async {
  final List<SyncOpRecord> operations = await dependencies.sync.all(
    projectId: projectId,
  );
  final List<PublishedScene> scenes = _scenesOf(operations);
  return _totalWords(scenes);
}

/// The public part of a project.
///
/// The owner, the members, the stage of the manuscript and the timestamps
/// stay on the server: a reader has no use for them, and they would say more
/// about the author than about the book.
Map<String, Object?> _projectJson(ProjectRecord project) {
  return <String, Object?>{
    'id': project.id,
    'title': project.title,
    'synopsis': project.synopsis,
    'language': project.language,
  };
}

/// The chapter the showcase publishes for a book.
///
/// The API does not know the chapters of a book yet — the structure routes
/// of the manuscript are not built — so the book is published as a single
/// chapter, and the scenes of the book are its scenes.
Map<String, Object?> _chapterJson(
  ProjectRecord project,
  List<PublishedScene> scenes,
) {
  return <String, Object?>{
    'id': project.id,
    'title': project.title,
    'synopsis': '',
    'scenes': scenes.map(_sceneJson).toList(growable: false),
  };
}

/// The public part of a scene: its title, its excerpt and its length.
Map<String, Object?> _sceneJson(PublishedScene scene) {
  return <String, Object?>{
    'id': scene.id,
    'title': scene.title,
    'excerpt': scene.excerpt,
    'wordCount': scene.wordCount,
  };
}

/// The number of words the scenes of the book hold.
int _totalWords(List<PublishedScene> scenes) {
  var total = 0;
  for (final PublishedScene scene in scenes) {
    total += scene.wordCount;
  }
  return total;
}

/// A scene of a published book, reduced to what a reader may see.
final class PublishedScene {
  /// Creates a scene of a published book.
  const PublishedScene({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.wordCount,
  });

  /// The identifier of the scene.
  final String id;

  /// The title of the scene.
  final String title;

  /// The excerpt of the scene.
  final String excerpt;

  /// The number of words the scene holds.
  final int wordCount;
}

/// The scenes of a book: one scene per synchronised document.
///
/// The document of a scene is the scene itself in version 1 (D-02), so the
/// journal of the project already holds the scenes of the book. The scenes
/// keep the order of the journal: a scene appears where it was written.
List<PublishedScene> _scenesOf(List<SyncOpRecord> operations) {
  final Map<String, List<SyncOpRecord>> byDocument =
      <String, List<SyncOpRecord>>{};
  for (final SyncOpRecord operation in operations) {
    byDocument
        .putIfAbsent(operation.docId, () => <SyncOpRecord>[])
        .add(operation);
  }

  final List<PublishedScene> scenes = <PublishedScene>[];
  for (final MapEntry<String, List<SyncOpRecord>> entry in byDocument.entries) {
    final CrdtDocument document = _documentOf(entry.key, entry.value);
    scenes.add(
      PublishedScene(
        id: entry.key,
        title: document.meta['title'] ?? '',
        excerpt: excerptOf(document),
        wordCount: WordCount.ofBlocks(
          document.blocks.where((Block block) => !block.deleted),
        ),
      ),
    );
  }
  return List<PublishedScene>.unmodifiable(scenes);
}

/// Rebuilds the document of a scene from the operations of the journal.
///
/// An operation that cannot be decoded is ignored, exactly as the tree of
/// the synchronisation route ignores it: the journal stays append-only and
/// the client keeps its own state.
CrdtDocument _documentOf(String docId, List<SyncOpRecord> operations) {
  CrdtDocument document = CrdtDocument.empty(DocumentId(docId));
  for (final SyncOpRecord operation in operations) {
    final SyncOp? decoded = _decode(operation);
    if (decoded == null) continue;
    document = document.apply(decoded);
  }
  return document;
}

/// Decodes an operation of the journal.
SyncOp? _decode(SyncOpRecord operation) {
  try {
    return SyncProtocol.decodeRecord(operation);
  } on Object {
    return null;
  }
}

/// The excerpt of a scene: its first paragraph.
///
/// The rule is the one of the application
/// (`apps/limpid_app/lib/src/domain/publication_repository.dart`): the
/// tombstones are ignored, the first paragraph that holds text wins, and a
/// long excerpt is cut on a word boundary.
String excerptOf(CrdtDocument document) {
  for (final Block block in document.blocks) {
    if (block.deleted) continue;
    if (block.type != BlockType.paragraph) continue;
    final String text = block.content.plainText.trim();
    if (text.isEmpty) continue;
    return truncateExcerpt(text);
  }
  return '';
}

/// Shortens an excerpt to [maxExcerptLength] characters.
///
/// The cut falls on a word boundary, so that a reader never reads a word cut
/// in half.
String truncateExcerpt(String text) {
  if (text.length <= maxExcerptLength) return text;
  final int boundary = text.lastIndexOf(' ', maxExcerptLength);
  final int end = boundary > 0 ? boundary : maxExcerptLength;
  return '${text.substring(0, end).trimRight()}$excerptEllipsis';
}
