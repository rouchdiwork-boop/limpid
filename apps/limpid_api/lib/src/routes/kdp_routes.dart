import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/kdp_database.dart';
import '../db/kdp_record.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../services/kdp_metadata.dart';
import '../services/kdp_service.dart';

/// Enregistre les routes de la publication Amazon KDP.
///
/// Les trois routes décrivent le cycle de la publication : la préparation
/// reconstruit le livre, produit le fichier EPUB et le PDF d'impression et
/// contrôle le dossier ; la liste et la lecture rendent la trace, pour que
/// l'auteur reprenne sa soumission plus tard.
///
/// La publication renvoie un lien de téléchargement, jamais le fichier :
/// un EPUB de plusieurs mégaoctets ne transite pas dans une réponse JSON.
void registerKdpRoutes(Router router, KdpDatabase database, AppConfig config) {
  final KdpService service = KdpService(database: database);

  router.post('/v1/publishing/kdp', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String projectId = body.requireString(
      'project_id',
      maxLength: maxProjectIdLength,
    );
    final KdpMetadata metadata = KdpMetadataReader.read(body);
    final KdpPublication publication = await service.prepare(
      auth: auth,
      projectId: projectId,
      metadata: metadata,
    );
    return ApiResponse.ok(
      await service.describe(publication),
      status: HttpStatus.created,
    );
  });

  router.get('/v1/publishing/kdp', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final String? projectId = request.url.queryParameters['project_id'];
    final List<KdpPublication> publications = await service.list(
      auth: auth,
      projectId: projectId,
    );
    final List<Object?> items = <Object?>[
      for (final KdpPublication publication in publications)
        await service.describe(publication),
    ];
    return ApiResponse.ok(items);
  });

  router.get('/v1/publishing/kdp/<publicationId>', (
    Request request,
    String publicationId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final KdpPublication? publication = await service.find(
      auth: auth,
      publicationId: publicationId,
    );
    if (publication == null) {
      throw const NotFoundException(
        message: "Cette publication n'existe pas ou n'est plus accessible.",
      );
    }
    return ApiResponse.ok(await service.describe(publication));
  });
}

/// La longueur maximale de l'identifiant d'un projet.
const int maxProjectIdLength = 128;
