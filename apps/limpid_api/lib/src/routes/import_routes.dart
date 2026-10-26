import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_import/limpid_import.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../db/quota_database.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/access_control.dart';
import '../services/account_word_count.dart';
import '../services/manuscript_import_service.dart';
import '../services/plan_catalog.dart';
import '../services/quota_service.dart';

/// Le nombre maximum de mots au-dela duquel la jauge n'est plus calcule.
///
/// Reconstruire les documents d'un compte coute cher : au-dela de ce
/// plafond, la limite de la formule est hors d'atteinte en pratique.
const int reachableImportWordLimit = 1000000;

/// Enregistre les routes de l'import d'un manuscrit.
///
/// La route reconnait le format du fichier, refuse un format inconnu et
/// un fichier illisible, puis **cree** la structure : un document par
/// chapitre, un bloc de titre par scene. Un import n'ecrase rien : il
/// ajoute des chapitres, et la suppression d'un chapitre importe passe par
/// la route de suppression habituelle.
///
/// [quota] porte le garde-fou des mots : il est verifie avant l'ecriture,
/// pour qu'un import ne fasse jamais passer un compte au-dela de sa
/// formule. Quand il est absent, le garde-fou est construit a partir des
/// dependances.
void registerImportRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  QuotaService? quota,
}) {
  final QuotaService? guard = quota ?? _quotaOf(dependencies);

  router.post('/v1/projects/<projectId>/import', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    await AccessControl.requireEditor(dependencies.projects, projectId, auth);

    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final String fileName = body.requireString('file_name', maxLength: 512);
    final String encoded = body.requireString('content');
    final String? contentType = body.optionalString(
      'content_type',
      maxLength: 255,
    );
    final Uint8List bytes = _decode(encoded);

    // Le nombre de mots est une jauge de la formule : elle est verifiee
    // avant l'ecriture, comme sur la route des operations.
    if (guard != null) {
      await guard.ensureGauge(
        userId: auth.userId,
        feature: QuotaFeature.words,
        current: await _currentWords(dependencies, auth, config),
      );
    }

    final ManuscriptImportService service = ManuscriptImportService(
      sync: dependencies.sync,
    );

    final ManuscriptImportResult result;
    try {
      result = await service.import(
        projectId: projectId,
        authorId: auth.userId,
        request: ImportRequest(
          fileName: fileName,
          bytes: bytes,
          contentType: contentType,
        ),
      );
    } on ImportException catch (error) {
      if (error.code == ImportErrorCodes.unsupportedFormat) {
        return _unsupportedMediaType(error);
      }
      throw _toAppException(error);
    }

    await dependencies.audit.record(
      AuditEntry(
        userId: auth.userId,
        action: 'project.imported',
        targetType: 'project',
        targetId: projectId,
        metadata: <String, Object?>{
          'format': result.format.name,
          'chapters': result.chapterCount,
          'scenes': result.sceneCount,
          'blocks': result.blockCount,
        },
        ip: clientIpOf(request),
      ),
    );

    return ApiResponse.ok(result.toJson(), status: HttpStatus.created);
  });
}

/// Le service de quota construit a partir des dependances, `null` quand la
/// base des formules n'est pas cablee.
QuotaService? _quotaOf(AppDependencies dependencies) {
  final QuotaDatabase? database = dependencies.quotas;
  if (database == null) return null;
  return QuotaService(
    database: database,
    dispatcher: dependencies.webhookDispatcher,
  );
}

/// Decode le contenu du fichier, refuse un contenu qui n'est pas du base64.
Uint8List _decode(String encoded) {
  final Uint8List bytes;
  try {
    bytes = base64.decode(encoded.trim());
  } on FormatException catch (error) {
    throw ValidationException(
      field: 'content',
      message: 'Le contenu du fichier n\'est pas du base64 valide.',
      details: <String, Object?>{'reason': error.message},
    );
  }
  if (bytes.isEmpty) {
    throw const ValidationException(
      field: 'content',
      message: 'Le fichier est vide.',
    );
  }
  return bytes;
}

/// Traduit un echec d'import en erreur de l'API.
///
/// Un fichier illisible repond 400 : le client sait alors que le fichier
/// est casse. Un fichier sans texte repond 409.
AppException _toAppException(ImportException error) {
  return switch (error.code) {
    ImportErrorCodes.empty => ConflictException(message: error.message),
    _ => ValidationException(field: 'content', message: error.message),
  };
}

/// La reponse d'un format inconnu.
///
/// Le code 415 dit au client que le **type** du fichier n'est pas accepte :
/// il distingue le format inconnu du fichier casse, et il indique les
/// formats que la route sait lire.
Response _unsupportedMediaType(ImportException error) {
  return ApiResponse.raw(
    ApiResponse.encode(<String, Object?>{
      'error': <String, Object?>{
        'code': error.code,
        'message': error.message,
        'details': <String, Object?>{
          'formats': ImportFormat.values
              .map((ImportFormat format) => format.name)
              .toList(growable: false),
        },
      },
    }),
    status: HttpStatus.unsupportedMediaType,
  );
}

/// Le nombre de mots ecrits par le compte sur l'ensemble de ses projets.
///
/// La reconstruction des documents est couteuse : elle n'est faite que si
/// le plafond de mots de la formule est **atteignable**.
Future<int> _currentWords(
  AppDependencies dependencies,
  AuthContext auth,
  AppConfig config,
) async {
  final QuotaDatabase? database = dependencies.quotas;
  final SubscriptionPlan plan = database == null
      ? SubscriptionPlan.free
      : (await database.planOf(auth.userId))?.plan ?? SubscriptionPlan.free;
  final int? limit = PlanCatalog.limitOf(plan, QuotaFeature.words);
  if (limit == null || limit > reachableImportWordLimit) return 0;

  return AccountWordCounter(
    projects: dependencies.projects,
    sync: dependencies.sync,
    pageLimit: config.maxPageLimit,
  ).countOf(auth.userId);
}
