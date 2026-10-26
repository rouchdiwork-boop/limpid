import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:limpid_api/src/auth/auth_middleware.dart';
import 'package:limpid_api/src/config/app_config.dart';
import 'package:limpid_api/src/db/export_job_record.dart';
import 'package:limpid_api/src/db/in_memory_quota_database.dart';
import 'package:limpid_api/src/logging/logger.dart';
import 'package:limpid_api/src/middleware/error_handler.dart';
import 'package:limpid_api/src/routes/quota_routes.dart';
import 'package:limpid_api/src/services/plan_catalog.dart';
import 'package:limpid_api/src/services/quota_gauges.dart';
import 'package:limpid_api/src/services/storage_usage.dart';
import 'package:limpid_api/src/storage/artifact_keys.dart';
import 'package:limpid_api/src/storage/object_storage.dart';
import 'package:limpid_api/src/storage/stored_object.dart';
import 'package:limpid_core/limpid_core.dart' hide ExportJobStatus;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'helpers/export_test_server.dart';
import 'helpers/test_server.dart';

void main() {
  group('jauges publiées', () {
    late TestServer server;
    late String projectId;

    setUp(() async {
      server = await startTestServer();
      await server.givePlan('user-1', SubscriptionPlan.writer);
      projectId = await _createProject(server.post, server.tokenFor('user-1'));
      await _writeChapter(server.post, server.tokenFor('user-1'), projectId);
    });

    tearDown(() async {
      await server.stop();
    });

    test('GET /v1/me/quota publie les trois jauges', () async {
      final Handler handler = _quotaHandler(server);

      final Response response = await handler(_get('/v1/me/quota'));

      expect(response.statusCode, 200);
      final Map<String, dynamic> body = await _body(response);
      final List<dynamic> quotas =
          (body['data'] as Map<String, dynamic>)['quotas'] as List<dynamic>;

      final Map<String, dynamic> projects = _quotaOf(quotas, 'projects');
      final Map<String, dynamic> words = _quotaOf(quotas, 'words');
      final Map<String, dynamic> storage = _quotaOf(quotas, 'storage_bytes');

      expect(projects['used'], 1);
      expect(projects['limit'], 10);
      expect(words['used'], 5);
      expect(words['limit'], 200000);
      expect(storage['used'], 0);
      expect(storage['limit'], 500 * 1024 * 1024);
    });

    test('GET /v1/me/quota publie le stockage réel du compte', () async {
      await server.objectStorage.put(
        key: '${ArtifactKeys.prefixOfProject(projectId)}livre.epub',
        bytes: Uint8List.fromList(List<int>.filled(2048, 0)),
        contentType: 'application/epub+zip',
      );

      final Handler handler = _quotaHandler(server);

      final Response response = await handler(_get('/v1/me/quota'));

      final Map<String, dynamic> body = await _body(response);
      final List<dynamic> quotas =
          (body['data'] as Map<String, dynamic>)['quotas'] as List<dynamic>;

      expect(_quotaOf(quotas, 'storage_bytes')['used'], 2048);
    });
  });

  group('garde-fou du stockage', () {
    late ExportTestServer server;
    late _AnnouncedStorage storage;
    late Map<String, String> auth;
    late String projectId;

    setUp(() async {
      storage = _AnnouncedStorage();
      server = await ExportTestServer.start(storage: storage);
      auth = <String, String>{
        'authorization': 'Bearer ${server.tokenFor('user-1')}',
      };
      projectId = await _createProject(server.post, server.tokenFor('user-1'));
      await _writeChapter(server.post, server.tokenFor('user-1'), projectId);
    });

    tearDown(() async {
      await server.stop();
    });

    test('refuse l\'export qui ferait dépasser la limite', () async {
      // La formule gratuite porte cent mégaoctets de stockage : l'artefact
      // déjà présent en annonce deux cents.
      storage.announcedBytes = 200 * 1024 * 1024;
      await storage.put(
        key: '${ArtifactKeys.prefixOfProject(projectId)}livre.epub',
        bytes: Uint8List.fromList(List<int>.filled(10, 0)),
        contentType: 'application/epub+zip',
      );

      final http.Response response = await server.post(
        '/v1/export/epub',
        headers: auth,
        body: <String, Object?>{'project_id': projectId},
      );

      // La route cree le travail : la taille de l'artefact n'est connue
      // qu'apres la fabrication, le garde-fou du stockage passe donc dans
      // le worker.
      expect(response.statusCode, 202);
      final String jobId =
          ((jsonDecode(response.body) as Map<String, dynamic>)['data']
                  as Map<String, dynamic>)['id']!
              as String;
      await server.runWorker();

      final ExportJobRecord? job = await server.job(jobId);
      expect(job!.status, ExportJobStatus.failed);
      expect(job.errorCode, 'plan_limit_reached');
      expect(job.error, contains('Stockage'));

      // L'artefact refuse n'est pas ecrit.
      expect(storage.keys, hasLength(1));
    });

    test('laisse passer l\'export qui tient dans la limite', () async {
      final AccountStorageUsage usage = AccountStorageUsage(
        projects: server.projects,
        storage: storage,
      );
      final int before = await usage.bytesOf('user-1');

      final http.Response response = await server.post(
        '/v1/export/epub',
        headers: auth,
        body: <String, Object?>{'project_id': projectId},
      );

      expect(response.statusCode, 202);
      await server.runWorker();
      final int after = await usage.bytesOf('user-1');
      expect(after - before, greaterThan(0));
      expect(storage.keys, hasLength(1));
    });
  });

  group('compteur des couvertures', () {
    late TestServer server;
    late Map<String, String> auth;

    setUp(() async {
      // La limite de débit ne doit pas mordre : le test enchaîne les
      // demandes de couverture.
      server = await startTestServer(
        configOverrides: <String, String>{'AI_RATE_LIMIT_CAPACITY': '100'},
      );
      await server.givePlan('user-1', SubscriptionPlan.writer);
      auth = <String, String>{
        'authorization': 'Bearer ${server.tokenFor('user-1')}',
      };
    });

    tearDown(() async {
      await server.stop();
    });

    test('une génération de couverture consomme le compteur', () async {
      final http.Response response = await server.post(
        '/v1/ai/generate',
        headers: auth,
        body: <String, Object?>{
          'prompt': 'Décris la couverture du roman.',
          'task': 'cover',
        },
      );

      expect(response.statusCode, 200);

      final int used = await _coverUsage(server);
      expect(used, 1);
    });

    test('une génération ordinaire ne consomme pas le compteur', () async {
      final http.Response response = await server.post(
        '/v1/ai/generate',
        headers: auth,
        body: <String, Object?>{
          'prompt': 'Décris la falaise.',
          'task': 'summarize',
        },
      );

      expect(response.statusCode, 200);
      expect(await _coverUsage(server), 0);
    });

    test(
      'refuse la couverture au-delà de la limite, avant l\'appel au modèle',
      () async {
        for (int index = 0; index < 5; index++) {
          final http.Response accepted = await server.post(
            '/v1/ai/generate',
            headers: auth,
            body: <String, Object?>{
              'prompt': 'Décris la couverture du roman.',
              'task': 'cover',
            },
          );
          expect(accepted.statusCode, 200);
        }
        expect(server.ai.generateCalls, 5);

        // La formule Écrivain porte cinq couvertures par mois : la
        // vingt-sixième demande est refusée, et le refus ne coûte rien au
        // fournisseur.
        for (int index = 5; index < 26; index++) {
          final http.Response refused = await server.post(
            '/v1/ai/generate',
            headers: auth,
            body: <String, Object?>{
              'prompt': 'Décris la couverture du roman.',
              'task': 'cover',
            },
          );

          expect(refused.statusCode, 402);
          final Map<String, dynamic> body =
              jsonDecode(refused.body) as Map<String, dynamic>;
          final Map<String, dynamic> error =
              body['error'] as Map<String, dynamic>;
          expect(error['code'], 'plan_limit_reached');
          final Map<String, dynamic> details =
              error['details'] as Map<String, dynamic>;
          expect(details['feature'], 'ai_covers');
          expect(details['limit'], 5);
        }

        expect(server.ai.generateCalls, 5);
        expect(await _coverUsage(server), 5);
      },
    );
  });
}

/// Le compteur des couvertures du compte, dans le mois courant.
Future<int> _coverUsage(TestServer server) async {
  final InMemoryQuotaDatabase database =
      server.dependencies.quotas! as InMemoryQuotaDatabase;
  return database.usageOf(
    userId: 'user-1',
    feature: QuotaFeature.aiCovers,
    periodKey: _monthKey(),
  );
}

/// La clé du mois courant.
String _monthKey() {
  final DateTime now = DateTime.now().toUtc();
  final String month = now.month.toString().padLeft(2, '0');
  return '${now.year}-$month';
}

/// Le gestionnaire de la route des quotas, câblé sur les jauges.
Handler _quotaHandler(TestServer server) {
  final Router router = Router();
  registerQuotaRoutes(
    router,
    server.dependencies.quotas!,
    testConfig(),
    gauges: AccountQuotaGauges(
      projects: server.projects,
      sync: server.sync,
      storage: server.objectStorage,
    ),
  );
  return _handler(router);
}

/// Le gestionnaire qui transforme les erreurs en réponses.
Handler _handler(Router router) {
  final Logger logger = Logger(level: LogLevel.error, sink: (String line) {});
  return errorHandlerMiddleware(logger: logger)(router.call);
}

/// Le compteur d'une fonctionnalité, dans la réponse des quotas.
Map<String, dynamic> _quotaOf(List<dynamic> quotas, String feature) {
  return quotas.cast<Map<String, dynamic>>().firstWhere(
    (Map<String, dynamic> item) => item['feature'] == feature,
  );
}

/// L'appel HTTP du serveur de test.
///
/// Les deux serveurs du dépôt — le serveur complet et celui de l'export —
/// répondent de la meme facon : l'appel HTTP est ce dont l'aide a besoin.
typedef _Post =
    Future<http.Response> Function(
      String path, {
      Object? body,
      Map<String, String> headers,
    });

/// Crée un livre et renvoie son identifiant.
Future<String> _createProject(_Post post, String token) async {
  final http.Response response = await post(
    '/v1/projects',
    headers: <String, String>{'authorization': 'Bearer $token'},
    body: <String, Object?>{'title': 'Manuscrit'},
  );
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return (body['data'] as Map<String, dynamic>)['id'] as String;
}

/// Écrit un chapitre de cinq mots dans le livre [projectId].
Future<void> _writeChapter(_Post post, String token, String projectId) async {
  await post(
    '/v1/projects/$projectId/ops',
    headers: <String, String>{'authorization': 'Bearer $token'},
    body: <String, Object?>{
      'operations': <dynamic>[
        <String, Object?>{
          'op_id': 'op-1',
          'doc_id': 'doc-1',
          'lamport': 1,
          'author_id': 'user-1',
          'type': 'insertBlock',
          'payload': <String, Object?>{
            'block_id': 'block-1',
            'parent_id': null,
            'order_key': '5',
            'type': 'paragraph',
            'content': 'Il pleuvait sur la falaise.',
          },
          'schema_version': 1,
        },
      ],
    },
  );
}

/// Le contexte d'authentification du compte de test.
Map<String, Object> _authContext() {
  return <String, Object>{
    authContextKey: const AuthContext(
      userId: 'user-1',
      email: 'user-1@example.test',
      claims: <String, dynamic>{},
    ),
  };
}

/// Une requête authentifiée.
Request _get(String path) {
  return Request(
    'GET',
    Uri.parse('http://localhost$path'),
    context: _authContext(),
  );
}

/// Le corps JSON décodé d'une réponse.
Future<Map<String, dynamic>> _body(Response response) async {
  final String raw = await response.readAsString();
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// Un stockage qui annonce une taille à la demande.
///
/// La mesure du stockage se fait sur la liste des objets : un test peut
/// donc annoncer la taille d'un artefact sans l'écrire.
final class _AnnouncedStorage implements ObjectStorage, ObjectStorageReader {
  final Map<String, Uint8List> _objects = <String, Uint8List>{};

  /// La taille annoncée pour les objets, quand elle est forcée.
  int? announcedBytes;

  /// Les clés stockées.
  List<String> get keys => List<String>.unmodifiable(_objects.keys);

  @override
  Future<void> put({
    required String key,
    required Uint8List bytes,
    required String contentType,
  }) async {
    _objects[key] = bytes;
  }

  @override
  Future<String> presignedUrl({
    required String key,
    required Duration expires,
  }) async {
    return 'https://storage.test/$key?expires=${expires.inSeconds}';
  }

  @override
  Future<List<String>> listKeys({required String prefix}) async {
    return List<String>.unmodifiable(
      _objects.keys.where((String key) => key.startsWith(prefix)),
    );
  }

  @override
  Future<List<StoredObject>> listObjects({required String prefix}) async {
    final List<StoredObject> objects = _objects.entries
        .where(
          (MapEntry<String, Uint8List> entry) => entry.key.startsWith(prefix),
        )
        .map(
          (MapEntry<String, Uint8List> entry) => StoredObject(
            key: entry.key,
            sizeBytes: announcedBytes ?? entry.value.length,
          ),
        )
        .toList(growable: false);
    return List<StoredObject>.unmodifiable(objects);
  }

  @override
  Future<Uint8List?> readObject({required String key}) async => _objects[key];
}
