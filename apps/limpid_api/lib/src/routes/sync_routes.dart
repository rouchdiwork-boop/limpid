import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/quota_database.dart';
import '../db/sync_op_record.dart';
import '../db/sync_store.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../services/access_control.dart';
import '../services/account_word_count.dart';
import '../services/plan_catalog.dart';
import '../services/quota_service.dart';
import '../sync/sync_protocol.dart';
import '../sync/tree_builder.dart';

/// Le plafond de mots au-dela duquel la jauge n'est plus calcule.
///
/// Reconstruire les documents d'un compte coute cher : au-dela de ce
/// plafond, la limite de la formule est hors d'atteinte en pratique, et le
/// calcul couterait plus cher que la limite ne vaut.
const int reachableWordLimit = 1000000;

/// Registers the routes of the synchronisation.
void registerSyncRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  QuotaService? quota,
}) {
  router.get('/v1/projects/<projectId>/tree', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    await AccessControl.requireProject(dependencies.projects, projectId, auth);

    final List<SyncOpRecord> operations = await dependencies.sync.all(
      projectId: projectId,
    );
    final List<DocumentTree> trees = TreeBuilder.build(operations);
    return ApiResponse.ok(
      trees.map((DocumentTree tree) => tree.toJson()).toList(),
    );
  });

  router.post('/v1/projects/<projectId>/ops', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    await AccessControl.requireEditor(dependencies.projects, projectId, auth);

    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final List<dynamic> raw = body.requireList(
      'operations',
      maxLength: config.maxOperationsPerBatch,
    );

    final List<SyncOpRecord> operations = <SyncOpRecord>[];
    final List<Map<String, Object?>> rejected = <Map<String, Object?>>[];
    final Map<String, Set<String>> ownersByDoc = <String, Set<String>>{};
    for (final dynamic entry in raw) {
      if (entry is! Map<String, dynamic>) {
        rejected.add(<String, Object?>{
          'code': ErrorCodes.validationFailed,
          'message': 'Chaque opération doit être un objet JSON.',
          'field': 'operations',
        });
        continue;
      }
      try {
        final SyncOpRecord record = _toRecord(
          projectId,
          entry,
          authorId: auth.userId,
        );
        if (!await _mayWrite(
          dependencies.sync,
          ownersByDoc,
          projectId: projectId,
          docId: record.docId,
        )) {
          rejected.add(<String, Object?>{
            // The operation is identified when it carried an identifier: the
            // client has to know which one was refused.
            if (entry['op_id'] is String) 'op_id': entry['op_id'],
            'code': ErrorCodes.notFound,
            'message': "Ce document n'existe pas dans ce projet.",
            'field': 'doc_id',
          });
          continue;
        }
        operations.add(record);
      } on SchemaVersionException {
        rethrow;
      } on ClientAheadException {
        rethrow;
      } on AppException catch (error) {
        rejected.add(<String, Object?>{
          // The operation is identified when it carried an identifier: the
          // client has to know which one was refused.
          if (entry['op_id'] is String) 'op_id': entry['op_id'],
          'code': error.code,
          'message': error.message,
          'field': error is ValidationException ? error.field : 'operations',
        });
      }
    }

    // Le nombre de mots est une jauge de la formule : elle est verifiee
    // avant l'ecriture, pour que le compte ne depasse jamais son contrat.
    if (quota != null) {
      await quota.ensureGauge(
        userId: auth.userId,
        feature: QuotaFeature.words,
        current: await _currentWords(dependencies, auth, config),
      );
    }

    final AppendResult result = await dependencies.sync.append(
      projectId: projectId,
      operations: operations,
    );

    for (final SyncOpRecord operation in result.accepted) {
      dependencies.syncHub
          .broadcast(operation.projectId, operation.docId, <String, Object?>{
            'type': 'op',
            'seq': operation.lamport,
            'sent_at': operation.createdAt.toUtc().toIso8601String(),
            'payload': operation.toJson(),
          });
    }

    return ApiResponse.ok(<String, Object?>{
      'accepted': result.accepted
          .map((SyncOpRecord operation) => operation.toJson())
          .toList(),
      'duplicated': result.duplicated
          .map((SyncOpRecord operation) => operation.toJson())
          .toList(),
      'rejected': rejected,
      'lamport_ack': result.maxLamport,
    });
  });

  router.get('/v1/projects/<projectId>/ops', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    await AccessControl.requireProject(dependencies.projects, projectId, auth);

    final int since = _readSince(request, config);
    final List<SyncOpRecord> operations = await dependencies.sync.since(
      projectId: projectId,
      lamport: since,
      limit: config.maxOperationsPerBatch,
    );

    return ApiResponse.ok(
      operations.map((SyncOpRecord operation) => operation.toJson()).toList(),
    );
  });
}

int _readSince(Request request, AppConfig config) {
  final String? raw = request.url.queryParameters['since'];
  if (raw == null || raw.trim().isEmpty) return 0;
  final int? parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < 0) {
    throw const ValidationException(
      field: 'since',
      message: 'Le paramètre « since » doit être un entier positif ou nul.',
    );
  }
  return parsed;
}

SyncOpRecord _toRecord(
  String projectId,
  Map<String, dynamic> json, {
  required String authorId,
}) {
  final SyncOp op = SyncProtocol.decode(json);
  return SyncOpRecord(
    opId: _opIdOf(json),
    projectId: projectId,
    docId: op.doc.value,
    lamport: op.lamport,
    // The author is the authenticated caller: the server never trusts the
    // `author_id` carried by the payload, which would let a client sign an
    // operation with the identity of another account.
    authorId: authorId,
    type: op.kind,
    payload: _payloadOf(json),
    schemaVersion: json['schema_version'] is int
        ? json['schema_version']! as int
        : syncSchemaVersion,
    createdAt: DateTime.now().toUtc(),
  );
}

/// Whether an operation may be written for [docId] in [projectId].
///
/// The owners of the documents are read once per document and kept in
/// [ownersByDoc]: a batch carries few documents, and the journal is the
/// authority of the binding between a document and its project.
Future<bool> _mayWrite(
  SyncStore sync,
  Map<String, Set<String>> ownersByDoc, {
  required String projectId,
  required String docId,
}) async {
  Set<String>? owners = ownersByDoc[docId];
  if (owners == null) {
    owners = await sync.projectsOfDocument(docId);
    ownersByDoc[docId] = owners;
  }
  return owners.isEmpty || owners.contains(projectId);
}

String _opIdOf(Map<String, dynamic> json) {
  final Object? opId = json['op_id'];
  if (opId is String && opId.isNotEmpty) return opId;
  return UlidGenerator().generate().value;
}

Map<String, dynamic> _payloadOf(Map<String, dynamic> json) {
  final Object? payload = json['payload'];
  if (payload is Map<String, dynamic>) return payload;
  return const <String, dynamic>{};
}

/// Le nombre de mots ecrits par le compte sur l'ensemble de ses projets.
///
/// La reconstruction des documents est couteuse : elle n'est faite que si
/// le plafond de mots de la formule est **atteignable**. Au-dela, le
/// plafond est hors d'atteinte en pratique et la reconstruction couterait
/// plus cher que la limite ne vaut.
Future<int> _currentWords(
  AppDependencies dependencies,
  AuthContext auth,
  AppConfig config,
) async {
  final SubscriptionPlan plan = await _planOf(dependencies, auth.userId);
  final int? limit = PlanCatalog.limitOf(plan, QuotaFeature.words);
  if (limit == null || limit > reachableWordLimit) return 0;

  return AccountWordCounter(
    projects: dependencies.projects,
    sync: dependencies.sync,
    pageLimit: config.maxPageLimit,
  ).countOf(auth.userId);
}

/// La formule du compte, lue par la base des formules.
///
/// Un compte sans formule est un compte gratuit : c'est le service de quota
/// qui applique la formule gratuite, pas la base.
Future<SubscriptionPlan> _planOf(
  AppDependencies dependencies,
  String userId,
) async {
  final QuotaDatabase? database = dependencies.quotas;
  if (database == null) return SubscriptionPlan.free;
  final AccountPlan? plan = await database.planOf(userId);
  return plan?.plan ?? SubscriptionPlan.free;
}
