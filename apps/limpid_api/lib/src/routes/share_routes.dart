import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../db/project_record.dart';
import '../db/share_store.dart';
import '../db/sync_op_record.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../http/pagination.dart';
import '../middleware/rate_limiter.dart';
import '../services/share_service.dart';
import '../sync/tree_builder.dart';

/// La route de lecture d'un partage, sous son adresse canonique.
///
/// Le jeton est dans l'adresse : c'est lui qui ouvre le document, et il ne
/// donne aucun droit d'écriture.
const String shareDocumentRoute = '/v1/shares/<token>/document';

/// Le préfixe canonique de la route de lecture d'un partage.
const String shareDocumentRoutePrefix = '/v1/shares/';

/// Le suffixe de la route de lecture d'un partage.
const String shareDocumentRouteSuffix = '/document';

/// L'alias public de la route de lecture d'un partage.
///
/// L'alias vit sous le préfixe `/v1/public/`, que le middleware
/// d'authentification exempte déjà : la page d'un partage est une page
/// publique, comme la vitrine d'un livre. L'adresse canonique reste la
/// référence du contrat.
const String publicShareDocumentRoutePrefix = '/v1/public/shares/';

/// Le nombre de pages partagées qu'une adresse peut burstir.
const int shareReadRateLimitCapacity = 30;

/// Le nombre de pages partagées qu'une adresse regagne par seconde.
///
/// Un jeton qui fuit ne doit pas pouvoir être tried à l'infini.
const double shareReadRateLimitRefillPerSecond = 1;

/// L'en-tête qui dit aux robots de ne pas indexer la page.
///
/// Une page partagée n'est pas indexée : le risque du lot 3.
const String noIndexHeader = 'x-robots-tag';

/// La valeur de l'en-tête qui interdit l'indexation.
const String noIndexValue = 'noindex';

/// L'en-tête qui interdit le cache de la page.
const String noStoreHeader = 'cache-control';

/// La valeur de l'en-tête qui interdit le cache.
const String noStoreValue = 'no-store';

/// Enregistre les routes des partages en lecture.
///
/// Les routes `/v1/projects/<projectId>/shares`, `/v1/shares` et
/// `/v1/shares/<shareId>` décrivent le cycle de vie des partages : elles
/// s'adressent au propriétaire, et lisent le propriétaire dans le contexte
/// authentifié — jamais dans le corps de la requête.
///
/// La route `/v1/shares/<token>/document` est **publique** : un lecteur
/// n'a pas de compte, il n'a qu'un jeton. Elle rend le document du projet
/// partagé, en lecture seule, et ne rend rien d'autre : ni les autres
/// livres du compte, ni ses données personnelles.
///
/// [shares] porte les partages. [readRateLimitCapacity] existe pour que la
/// suite de tests puisse poser une limite étroite sans attendre.
void registerShareRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  required ShareStore shares,
  int readRateLimitCapacity = shareReadRateLimitCapacity,
}) {
  final ShareService service = ShareService(
    store: shares,
    projects: dependencies.projects,
  );
  final TokenBucketRateLimiter limiter = TokenBucketRateLimiter(
    capacity: readRateLimitCapacity,
    refillPerSecond: shareReadRateLimitRefillPerSecond,
  );
  final Middleware limit = rateLimitMiddleware(
    limiter: limiter,
    scope: 'share_read',
    applies: (Request request) =>
        isShareDocumentPath(request.requestedUri.path),
  );

  // -------------------------------------------------------------------
  // La création d'un partage.
  // -------------------------------------------------------------------

  router.post('/v1/projects/<projectId>/shares', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await _optionalBody(request, config);
    final int? hours = body.has('expires_in_hours')
        ? body.requireInt('expires_in_hours')
        : null;

    final CreatedShare created = await service.create(
      ownerId: auth.userId,
      projectId: projectId,
      lifetimeHours: hours,
    );
    await _trace(
      request,
      dependencies.audit,
      userId: auth.userId,
      action: 'share.created',
      targetType: 'share',
      targetId: created.record.id,
      metadata: <String, Object?>{
        'project_id': created.record.projectId,
        'expires_at': created.record.expiresAt.toUtc().toIso8601String(),
      },
    );

    // Le jeton ne sort qu'ici : il n'est jamais rendu une seconde fois.
    return ApiResponse.ok(<String, Object?>{
      ...created.record.toJson(),
      'token': created.token,
    }, status: HttpStatus.created);
  });

  // -------------------------------------------------------------------
  // La liste des partages.
  // -------------------------------------------------------------------

  router.get('/v1/shares', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final PageRequest page = PageRequest.fromQuery(
      request.url.queryParameters,
      defaultLimit: config.defaultPageLimit,
      maxLimit: config.maxPageLimit,
    );
    final SharePage result = await service.list(
      ownerId: auth.userId,
      limit: page.limit,
      cursor: page.cursor,
    );
    return ApiResponse.paginated(
      items: result.items
          .map((ShareRecord share) => share.toJson())
          .toList(growable: false),
      total: result.total,
      page: page.page,
      limit: page.limit,
      nextCursor: result.nextCursor,
    );
  });

  // -------------------------------------------------------------------
  // La révocation d'un partage.
  // -------------------------------------------------------------------

  router.delete('/v1/shares/<shareId>', (
    Request request,
    String shareId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final ShareRecord revoked = await service.revoke(
      ownerId: auth.userId,
      shareId: shareId,
    );
    await _trace(
      request,
      dependencies.audit,
      userId: auth.userId,
      action: 'share.revoked',
      targetType: 'share',
      targetId: revoked.id,
      metadata: <String, Object?>{
        'project_id': revoked.projectId,
        'expires_at': revoked.expiresAt.toUtc().toIso8601String(),
      },
    );
    return ApiResponse.ok(revoked.toJson());
  });

  // -------------------------------------------------------------------
  // La lecture d'un partage, sans compte.
  // -------------------------------------------------------------------

  router.get(shareDocumentRoute, (Request request, String token) async {
    return limit(
      (Request request) => _serveDocument(dependencies, service, token),
    )(request);
  });

  router.get('$publicShareDocumentRoutePrefix<token>/document', (
    Request request,
    String token,
  ) async {
    return limit(
      (Request request) => _serveDocument(dependencies, service, token),
    )(request);
  });
}

/// Indique si [path] est la route de lecture d'un partage.
///
/// La reconnaissance est **précise** : seule la forme
/// `/v1/shares/<jeton>/document` est publique. Les autres routes de
/// `/v1/shares/` appartiennent au propriétaire et doivent garder leur
/// jeton de session : un préfixe trop large ouvrirait la révocation à
/// quiconque.
bool isShareDocumentPath(String path) {
  if (path.startsWith(publicShareDocumentRoutePrefix)) {
    return _isDocumentTail(
      path.substring(publicShareDocumentRoutePrefix.length),
    );
  }
  if (path.startsWith(shareDocumentRoutePrefix)) {
    return _isDocumentTail(path.substring(shareDocumentRoutePrefix.length));
  }
  return false;
}

/// Indique si [tail] est le jeton suivi du suffixe de la route de lecture.
bool _isDocumentTail(String tail) {
  if (!tail.endsWith(shareDocumentRouteSuffix)) return false;
  final String token = tail.substring(
    0,
    tail.length - shareDocumentRouteSuffix.length,
  );
  return token.isNotEmpty && !token.contains('/');
}

/// Rend le document du projet partagé, en lecture seule.
///
/// Un partage inconnu, révoqué ou expiré répond le même `404` : les trois
/// cas doivent être indiscernables, pour ne pas dire à un tiers qu'un
/// partage a existé. Jamais un `403`.
Future<Response> _serveDocument(
  AppDependencies dependencies,
  ShareService service,
  String token,
) async {
  final ShareRecord? share = await service.resolve(token);
  if (share == null) throw const NotFoundException();

  // Le livre doit encore exister : un partage d'un livre supprimé ne
  // rend rien.
  final ProjectAccess? access = await dependencies.projects.access(
    projectId: share.projectId,
    userId: share.ownerId,
  );
  if (access == null) throw const NotFoundException();

  final List<SyncOpRecord> operations = await dependencies.sync.all(
    projectId: access.project.id,
  );
  final List<DocumentTree> trees = TreeBuilder.build(operations);

  return ApiResponse.ok(
    <String, Object?>{
      'project': _projectJson(access.project),
      'documents': trees.map(_documentJson).toList(growable: false),
      'shared_at': share.createdAt.toUtc().toIso8601String(),
      'expires_at': share.expiresAt.toUtc().toIso8601String(),
    },
    headers: <String, String>{
      noIndexHeader: noIndexValue,
      noStoreHeader: noStoreValue,
    },
  );
}

/// La partie publique d'un projet.
///
/// Le propriétaire, les collaborateurs, l'étape du manuscrit et les
/// horodatages restent sur le serveur : un lecteur n'en a aucun usage, et
/// ils en diraient plus sur l'auteur que sur le livre.
Map<String, Object?> _projectJson(ProjectRecord project) {
  return <String, Object?>{
    'id': project.id,
    'title': project.title,
    'synopsis': project.synopsis,
    'language': project.language,
  };
}

/// Le document partagé, tel que le lecteur le voit.
///
/// L'auteur des blocs ne figure pas dans la projection : l'identifiant du
/// compte est une donnée personnelle, et le lecteur n'en a pas besoin.
Map<String, Object?> _documentJson(DocumentTree tree) {
  return <String, Object?>{
    'doc_id': tree.docId,
    'lamport': tree.lamport,
    'meta': tree.meta,
    'operation_count': tree.operationCount,
    'blocks': tree.blocks.map(_blockJson).toList(growable: false),
  };
}

/// Le bloc partagé, tel que le lecteur le voit.
Map<String, Object?> _blockJson(BlockNode block) {
  return <String, Object?>{
    'id': block.id,
    'parent_id': block.parentId,
    'order_key': block.orderKey,
    'type': block.type,
    'content': block.content,
    'lamport': block.lamport,
    'deleted': block.deleted,
    'version': block.version,
    'marks': block.marks,
    'children': block.children.map(_blockJson).toList(growable: false),
  };
}

/// Trace une action sensible dans le journal d'audit.
///
/// Aucun secret ne figure dans [metadata] : la trace dit ce qui a été
/// fait, jamais le jeton qui l'a permis.
Future<void> _trace(
  Request request,
  AuditLog journal, {
  required String userId,
  required String action,
  required String targetType,
  required String targetId,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return journal.record(
    AuditEntry(
      userId: userId,
      action: action,
      targetType: targetType,
      targetId: targetId,
      metadata: metadata,
      ip: clientIpOf(request),
    ),
  );
}

/// Lit le corps de la requête, quand il y en a un.
///
/// Créer un partage n'a pas besoin de corps : le corps vide est un corps
/// sans lifetime. Un corps trop gros est refusé comme sur les autres
/// routes.
Future<JsonBody> _optionalBody(Request request, AppConfig config) async {
  final int? length = request.contentLength;
  if (length != null && length > config.maxBodyBytes) {
    throw PayloadTooLargeException(
      limitBytes: config.maxBodyBytes,
      message: 'Le corps de la requête dépasse la taille maximale autorisée.',
    );
  }
  final String raw = await request.readAsString();
  if (raw.trim().isEmpty) return const JsonBody(<String, dynamic>{});
  return JsonBody.decode(raw);
}
