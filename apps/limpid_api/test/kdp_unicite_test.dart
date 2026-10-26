import 'dart:convert';

import 'package:limpid_api/src/auth/auth_middleware.dart';
import 'package:limpid_api/src/config/app_config.dart';
import 'package:limpid_api/src/db/in_memory_kdp_database.dart';
import 'package:limpid_api/src/db/in_memory_kdp_deposit_store.dart';
import 'package:limpid_api/src/db/in_memory_project_store.dart';
import 'package:limpid_api/src/db/in_memory_sync_store.dart';
import 'package:limpid_api/src/db/kdp_database.dart';
import 'package:limpid_api/src/db/kdp_deposit_record.dart';
import 'package:limpid_api/src/db/kdp_deposit_store.dart';
import 'package:limpid_api/src/db/kdp_record.dart';
import 'package:limpid_api/src/db/project_record.dart';
import 'package:limpid_api/src/db/sync_op_record.dart';
import 'package:limpid_api/src/logging/logger.dart';
import 'package:limpid_api/src/middleware/error_handler.dart';
import 'package:limpid_api/src/routes/kdp_publishing_routes.dart';
import 'package:limpid_api/src/routes/kdp_routes.dart';
import 'package:limpid_api/src/services/kdp_gateway.dart';
import 'package:limpid_api/src/services/kdp_publishing_service.dart';
import 'package:limpid_api/src/storage/object_storage.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

/// La réponse décodée de l'API de publication.
final class Answer {
  /// Crée une réponse décodée.
  const Answer(this.statusCode, this.body);

  /// Le code de statut HTTP.
  final int statusCode;

  /// Le corps JSON de la réponse.
  final Map<String, dynamic> body;

  /// La charge utile de la réponse.
  Map<String, dynamic> get data => body['data'] as Map<String, dynamic>;

  /// La liste de la réponse.
  List<dynamic> get items => body['data'] as List<dynamic>;

  /// L'erreur de la réponse.
  Map<String, dynamic> get error => body['error'] as Map<String, dynamic>;

  /// Les détails de l'erreur.
  Map<String, dynamic> get details => error['details'] as Map<String, dynamic>;
}

/// Une passerelle d'Amazon doublée, qui rend un verdict scripté.
final class FakeKdpGateway implements KdpGateway {
  /// Les demandes reçues, pour les assertions.
  final List<KdpSubmissionRequest> requests = <KdpSubmissionRequest>[];

  @override
  Future<KdpSubmissionOutcome> submit(KdpSubmissionRequest request) async {
    requests.add(request);
    return const KdpSubmissionAccepted('amazon-1');
  }
}

/// L'API de publication Amazon KDP, servie en mémoire.
///
/// Le serveur est un routeur réel : les erreurs métier deviennent des
/// réponses HTTP comme en production. Les routes de préparation et celles
/// de dépôt partagent la même base et la même trace de dépôts : c'est
/// l'ensemble qui dit si une fiche et un dépôt sont uniques.
final class KdpApi {
  KdpApi._(
    this._handler,
    this.storage,
    this.database,
    this.deposits,
    this.gateway,
  );

  final Handler _handler;

  /// Le stockage qui reçoit les fichiers produits.
  final InMemoryObjectStorage storage;

  /// La base des publications.
  final KdpDatabase database;

  /// La trace des dépôts.
  final KdpDepositStore deposits;

  /// La porte de sortie vers Amazon.
  final FakeKdpGateway gateway;

  /// Démarre l'API sur une base en mémoire.
  ///
  /// [plan] est la formule du compte : `null` pour un compte sans formule.
  /// [words] est la longueur du manuscrit : un livre complet est necessaire
  /// pour que le dossier passe le controle de soumission.
  static Future<KdpApi> start({String? plan = 'pro', int words = 12}) async {
    final InMemoryProjectStore projects = InMemoryProjectStore();
    final InMemorySyncStore sync = InMemorySyncStore();
    final InMemoryObjectStorage storage = InMemoryObjectStorage();
    final InMemoryKdpDepositStore deposits = InMemoryKdpDepositStore();
    final FakeKdpGateway gateway = FakeKdpGateway();
    final KdpDatabase database = InMemoryKdpDatabase(
      planLookup: (String userId) async => plan,
      artefacts: storage,
      projects: projects,
      sync: sync,
    );

    final ProjectRecord project = await projects.create(
      ownerId: 'author-1',
      title: 'La Falaise',
      synopsis: 'Un roman.',
      status: ManuscriptStatus.draft,
      language: 'fr-FR',
      orderKey: '5',
    );
    await sync.append(
      projectId: project.id,
      operations: _operations(project.id, words),
    );
    final ProjectRecord other = await projects.create(
      ownerId: 'author-1',
      title: 'Le Promontoire',
      synopsis: 'Un autre roman.',
      status: ManuscriptStatus.draft,
      language: 'fr-FR',
      orderKey: '7',
    );
    await sync.append(
      projectId: other.id,
      operations: _operations(other.id, words),
    );

    final Router router = Router();
    registerKdpRoutes(router, database, _config());
    registerKdpPublishingRoutes(
      router,
      KdpPublishingService(
        publications: database,
        deposits: deposits,
        gateway: gateway,
      ),
      _config(),
    );

    final KdpApi api = KdpApi._(
      errorHandlerMiddleware(logger: _logger())(router.call),
      storage,
      database,
      deposits,
      gateway,
    );
    api.projectId = project.id;
    api.otherProjectId = other.id;
    return api;
  }

  /// L'identifiant du projet publié.
  late final String projectId;

  /// L'identifiant d'un second projet du compte.
  late final String otherProjectId;

  /// Envoie une requête authentifiée par [userId] et décode la réponse.
  Future<Answer> send(
    String method,
    String path, {
    String userId = 'author-1',
    Map<String, Object?>? body,
  }) async {
    final Request request = Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: body == null
          ? null
          : <String, Object>{'content-type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
      context: <String, Object>{
        authContextKey: AuthContext(
          userId: userId,
          email: '',
          claims: const <String, dynamic>{},
        ),
      },
    );
    final Response response = await _handler(request);
    final String raw = await response.readAsString();
    return Answer(response.statusCode, jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Prépare une publication du projet.
  Future<Answer> prepare({
    Map<String, Object?> metadata = const <String, Object?>{},
    String userId = 'author-1',
    String? projectId,
  }) {
    return send(
      'POST',
      '/v1/publishing/kdp',
      userId: userId,
      body: <String, Object?>{
        'project_id': projectId ?? this.projectId,
        'title': 'La Falaise',
        'author': 'Camille Rivière',
        'isbn': '9782264000002',
        ...metadata,
      },
    );
  }

  /// Dépose le dossier de la publication [publicationId].
  Future<Answer> deposit(String publicationId) {
    return send(
      'POST',
      '/v1/publishing/kdp/deposits',
      body: <String, Object?>{'publication_id': publicationId},
    );
  }

  /// La configuration minimale du serveur de test.
  ///
  /// Les identifiants Amazon sont là : la route de dépôt refuse proprement
  /// quand la distribution n'est pas configurée, et ce test veut justement
  /// mesurer le deduplonnage du dépôt.
  static AppConfig _config() {
    return AppConfig.fromEnvironment(<String, String>{
      'PORT': '0',
      'SUPABASE_URL': 'https://project.test',
      'LOG_LEVEL': 'warning',
      'AMAZON_KDP_CLIENT_ID': 'client-id',
      'AMAZON_KDP_CLIENT_SECRET': 'client-secret',
      'AMAZON_KDP_REFRESH_TOKEN': 'refresh-token',
    });
  }

  /// Le logger silencieux du test.
  static Logger _logger() {
    return Logger(level: LogLevel.warning, sink: (String line) {});
  }
}

/// Les opérations du manuscrit : un chapitre et son paragraphe.
List<SyncOpRecord> _operations(String projectId, int words) {
  return <SyncOpRecord>[
    SyncOpRecord(
      opId: 'op-1',
      projectId: projectId,
      docId: 'doc-1',
      lamport: 1,
      authorId: 'author-1',
      type: 'insertBlock',
      payload: <String, dynamic>{
        'block_id': 'block-1',
        'parent_id': null,
        'order_key': '5',
        'type': 'heading1',
        'content': 'Le premier chapitre',
      },
      schemaVersion: 1,
      createdAt: DateTime.utc(2026),
    ),
    SyncOpRecord(
      opId: 'op-2',
      projectId: projectId,
      docId: 'doc-1',
      lamport: 2,
      authorId: 'author-1',
      type: 'insertBlock',
      payload: <String, dynamic>{
        'block_id': 'block-2',
        'parent_id': 'block-1',
        'order_key': '7',
        'type': 'paragraph',
        'content': _text(words),
      },
      schemaVersion: 1,
      createdAt: DateTime.utc(2026),
    ),
  ];
}

/// Un texte de [words] mots.
String _text(int words) => List<String>.filled(words, 'mot').join(' ');

void main() {
  group('unicité de la fiche KDP', () {
    late KdpApi api;

    setUp(() async {
      api = await KdpApi.start();
    });

    test('préparer deux fois le même livre laisse une fiche', () async {
      final Answer first = await api.prepare();
      final Answer second = await api.prepare();

      expect(first.statusCode, 201);
      expect(second.statusCode, 201);

      final Answer listed = await api.send('GET', '/v1/publishing/kdp');
      expect(listed.items, hasLength(1));
    });

    test('la fiche garde son identifiant', () async {
      final Answer first = await api.prepare();
      final Answer second = await api.prepare();

      expect(second.data['id'], first.data['id']);
    });

    test('les fichiers produits ne sont pas dupliqués', () async {
      await api.prepare();
      await api.prepare();

      // Les deux fichiers sont ecrits sous le meme prefixe : la seconde
      // preparation remplace les premiers, elle n'en empile pas.
      expect(api.storage.keys, hasLength(2));
    });

    test('la fiche porte la trace de la dernière préparation', () async {
      final Answer first = await api.prepare();
      final Answer second = await api.prepare(
        metadata: <String, Object?>{'title': 'La Falaise, tome deux'},
      );

      expect(second.data['id'], first.data['id']);
      expect(second.data['title'], 'La Falaise, tome deux');
    });

    test('un ISBN déjà porté par une autre fiche est refusé', () async {
      final Answer first = await api.prepare();
      expect(first.statusCode, 201);

      // Un autre livre du compte prend le meme ISBN : les deux fiches
      // designeraient le meme ouvrage imprime.
      final Answer second = await api.prepare(
        projectId: api.otherProjectId,
        metadata: <String, Object?>{'isbn': '9782264000002'},
      );

      expect(second.statusCode, 409);
      expect(second.error['code'], 'conflict');
      expect(second.error['message'], contains('9782264000002'));
      expect(second.details['isbn'], '9782264000002');
    });

    test('une fiche reprend son propre ISBN', () async {
      final Answer first = await api.prepare();
      expect(first.statusCode, 201);

      // La meme fiche, preparee une seconde fois : elle reprend son ISBN.
      final Answer second = await api.prepare();

      expect(second.statusCode, 201);
      expect(second.data['id'], first.data['id']);
      expect(second.data['isbn'], '9782264000002');
    });

    test('un ISBN libre est accepté', () async {
      final Answer answer = await api.prepare(
        metadata: <String, Object?>{'isbn': '9782264000019'},
      );

      expect(answer.statusCode, 201);
      expect(answer.data['isbn'], '9782264000019');
    });

    test('le dépôt ne part pas une seconde fois', () async {
      // Un livre complet : le dossier passe le controle de soumission, le
      // depot part chez Amazon.
      final KdpApi complete = await KdpApi.start(words: 20000);
      final Answer prepared = await complete.prepare();
      final Answer again = await complete.prepare();
      final String publicationId = prepared.data['id']! as String;
      expect(again.data['id'], publicationId);
      expect(prepared.data['status'], 'ready');

      final Answer deposited = await complete.deposit(publicationId);
      final Answer depositedAgain = await complete.deposit(publicationId);

      expect(deposited.statusCode, 200);
      expect(depositedAgain.statusCode, 200);
      expect(depositedAgain.data['id'], deposited.data['id']);

      final List<KdpDeposit> deposits = await complete.deposits.listDeposits(
        userId: 'author-1',
      );
      expect(deposits, hasLength(1));

      // Amazon n'a recu le dossier qu'une fois.
      expect(complete.gateway.requests, hasLength(1));
    });
  });

  group('base en mémoire', () {
    test('la fiche du projet se relit', () async {
      final KdpApi api = await KdpApi.start();

      final Answer prepared = await api.prepare();

      final KdpPublication? found = await api.database.findPublicationByProject(
        projectId: api.projectId,
      );
      expect(found?.id, prepared.data['id']);
    });

    test('la fiche par ISBN se relit', () async {
      final KdpApi api = await KdpApi.start();

      await api.prepare();

      final KdpPublication? found = await api.database.findPublicationByIsbn(
        isbn: '9782264000002',
      );
      expect(found, isNotNull);
      expect(found?.isbn, '9782264000002');
    });

    test('un ISBN inconnu ne porte aucune fiche', () async {
      final KdpApi api = await KdpApi.start();

      final KdpPublication? found = await api.database.findPublicationByIsbn(
        isbn: '9782264000099',
      );
      expect(found, isNull);
    });
  });
}
