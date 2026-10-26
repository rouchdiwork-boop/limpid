import 'dart:convert';
import 'dart:io';

import 'package:limpid_api/src/auth/auth_middleware.dart';
import 'package:limpid_api/src/config/app_config.dart';
import 'package:limpid_api/src/db/in_memory_kdp_database.dart';
import 'package:limpid_api/src/db/in_memory_project_store.dart';
import 'package:limpid_api/src/db/in_memory_sync_store.dart';
import 'package:limpid_api/src/db/kdp_database.dart';
import 'package:limpid_api/src/db/project_record.dart';
import 'package:limpid_api/src/db/sqlite_database.dart';
import 'package:limpid_api/src/db/sqlite_kdp_database.dart';
import 'package:limpid_api/src/db/sqlite_statement_splitter.dart';
import 'package:limpid_api/src/db/sqlite_sync_store.dart';
import 'package:limpid_api/src/db/sync_op_record.dart';
import 'package:limpid_api/src/logging/logger.dart';
import 'package:limpid_api/src/middleware/error_handler.dart';
import 'package:limpid_api/src/routes/kdp_routes.dart';
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

  /// Les codes des problèmes relevés par le contrôle de soumission.
  List<String> get issueCodes {
    final List<Object?> issues = data['issues']! as List<Object?>;
    return <String>[
      for (final Object? issue in issues)
        (issue! as Map<String, dynamic>)['code']! as String,
    ];
  }
}

/// L'API de publication Amazon KDP, servie en mémoire.
///
/// Le serveur est un routeur réel : les erreurs métier deviennent des
/// réponses HTTP comme en production.
final class KdpApi {
  KdpApi._(this._handler, this.storage, this.dispose);

  final Handler _handler;

  /// Le stockage qui reçoit les fichiers produits.
  final InMemoryObjectStorage storage;

  /// Libère les ressources de l'API.
  final Future<void> Function() dispose;

  /// Démarre l'API sur une base en mémoire.
  ///
  /// [plan] est la formule du compte : `null` pour un compte sans formule.
  /// [words] est le nombre de mots du manuscrit.
  static Future<KdpApi> start({String? plan = 'pro', int words = 12}) async {
    final InMemoryProjectStore projects = InMemoryProjectStore();
    final InMemorySyncStore sync = InMemorySyncStore();
    final InMemoryObjectStorage storage = InMemoryObjectStorage();
    final KdpDatabase database = InMemoryKdpDatabase(
      planLookup: _planReader(plan),
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

    final KdpApi api = KdpApi._(
      KdpApi._handlerOf(database),
      storage,
      () async {},
    );
    api.projectId = project.id;
    return api;
  }

  /// L'identifiant du projet publié.
  late final String projectId;

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

  /// Prépare une publication avec des métadonnées complètes.
  Future<Answer> prepare({
    Map<String, Object?> metadata = const <String, Object?>{},
    String userId = 'author-1',
  }) {
    return send(
      'POST',
      '/v1/publishing/kdp',
      userId: userId,
      body: <String, Object?>{
        'project_id': projectId,
        ..._metadata(),
        ...metadata,
      },
    );
  }

  /// Les métadonnées d'une publication complète.
  static Map<String, Object?> _metadata() {
    return <String, Object?>{
      'title': 'La Falaise',
      'author': 'Camille Rivière',
      'description': 'Un roman maritime sur une côte battue par les vents.',
      'keywords': <String>['roman maritime', 'falaise', 'tempête'],
      'categories': <String>['Romans français', 'Littérature maritime'],
      'isbn': '9782264000002',
    };
  }

  /// Le routeur de l'API.
  static Handler _handlerOf(KdpDatabase database) {
    final Router router = Router();
    registerKdpRoutes(router, database, _config());
    final Logger logger = Logger(
      level: LogLevel.warning,
      sink: (String line) {},
    );
    return errorHandlerMiddleware(logger: logger)(router.call);
  }

  /// La configuration minimale du serveur de test.
  static AppConfig _config() {
    return AppConfig.fromEnvironment(<String, String>{
      'PORT': '0',
      'SUPABASE_URL': 'https://project.test',
      'LOG_LEVEL': 'warning',
    });
  }
}

/// La lecture de la formule du compte.
Future<String?> Function(String userId) _planReader(String? plan) {
  return (String userId) async => plan;
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
  group('préparation d\'une publication', () {
    late KdpApi api;

    setUp(() async {
      api = await KdpApi.start();
    });

    tearDown(() async {
      await api.dispose();
    });

    test('renvoie les liens de téléchargement des deux fichiers', () async {
      final Answer created = await api.prepare();

      expect(created.statusCode, 201);
      final Map<String, dynamic> artefacts =
          created.data['artefacts']! as Map<String, dynamic>;
      final Map<String, dynamic> epub =
          artefacts['epub']! as Map<String, dynamic>;
      final Map<String, dynamic> pdf =
          artefacts['pdf']! as Map<String, dynamic>;
      expect(epub['download_url'], contains('exports/${api.projectId}/kdp/'));
      expect(pdf['download_url'], contains('exports/${api.projectId}/kdp/'));
      expect(epub['size_in_bytes'], greaterThan(0));
      expect(pdf['size_in_bytes'], greaterThan(0));
    });

    test('dépose le EPUB et le PDF dans le stockage', () async {
      await api.prepare();

      expect(api.storage.keys, hasLength(2));
      expect(
        api.storage.keys.where((String key) => key.endsWith('.epub')),
        hasLength(1),
      );
      expect(
        api.storage.keys.where((String key) => key.endsWith('.pdf')),
        hasLength(1),
      );
    });

    test('écrit les fichiers sous le préfixe du projet', () async {
      await api.prepare();

      for (final String key in api.storage.keys) {
        expect(key, startsWith('exports/${api.projectId}/'));
      }
    });

    test('enregistre la trace et la relit', () async {
      final Answer created = await api.prepare();
      final String publicationId = created.data['id']! as String;

      final Answer listed = await api.send('GET', '/v1/publishing/kdp');
      expect(listed.statusCode, 200);
      expect(listed.items, hasLength(1));

      final Answer read = await api.send(
        'GET',
        '/v1/publishing/kdp/$publicationId',
      );
      expect(read.statusCode, 200);
      expect(read.data['title'], 'La Falaise');
      expect(read.data['author'], 'Camille Rivière');
      expect(read.data['isbn'], '9782264000002');
      expect(read.data['manuscript_version'], isNotEmpty);
      expect(read.data['created_at'], isNotEmpty);
    });

    test('filtre les publications par projet', () async {
      await api.prepare();

      final Answer listed = await api.send(
        'GET',
        '/v1/publishing/kdp?project_id=autre-projet',
      );
      expect(listed.statusCode, 404);
    });

    test('un compte étranger ne voit pas la publication', () async {
      final Answer created = await api.prepare();
      final String publicationId = created.data['id']! as String;

      final Answer read = await api.send(
        'GET',
        '/v1/publishing/kdp/$publicationId',
        userId: 'etranger',
      );
      expect(read.statusCode, 404);
      expect(read.error['code'], 'not_found');
    });

    test('un projet inconnu répond 404', () async {
      final Answer response = await api.send(
        'POST',
        '/v1/publishing/kdp',
        body: <String, Object?>{
          'project_id': 'projet-inconnu',
          'title': 'La Falaise',
          'author': 'Camille Rivière',
        },
      );

      expect(response.statusCode, 404);
      expect(response.error['code'], 'not_found');
    });

    test('la formule gratuite refuse la publication', () async {
      final KdpApi free = await KdpApi.start(plan: 'free');

      final Answer response = await free.prepare();

      expect(response.statusCode, 402);
      expect(response.error['code'], 'plan_limit_reached');
      expect(response.error['message'], contains('Pro'));
      await free.dispose();
    });

    test('un compte sans formule refuse la publication', () async {
      final KdpApi free = await KdpApi.start(plan: null);

      final Answer response = await free.prepare();

      expect(response.statusCode, 402);
      expect(response.error['code'], 'plan_limit_reached');
      await free.dispose();
    });
  });

  group('validation des métadonnées', () {
    late KdpApi api;

    setUp(() async {
      api = await KdpApi.start();
    });

    tearDown(() async {
      await api.dispose();
    });

    test('refuse un titre trop long et nomme le champ', () async {
      final Answer response = await api.prepare(
        metadata: <String, Object?>{'title': 'x' * 201},
      );

      expect(response.statusCode, 400);
      expect(response.error['code'], 'validation_failed');
      expect(response.error['message'], contains('title'));
    });

    test('refuse un résumé trop long', () async {
      final Answer response = await api.prepare(
        metadata: <String, Object?>{'description': 'x' * 4001},
      );

      expect(response.statusCode, 400);
      expect(response.error['message'], contains('description'));
    });

    test('refuse un huitième mot-clé', () async {
      final Answer response = await api.prepare(
        metadata: <String, Object?>{
          'keywords': <String>[
            'un',
            'deux',
            'trois',
            'quatre',
            'cinq',
            'six',
            'sept',
            'huit',
          ],
        },
      );

      expect(response.statusCode, 400);
      expect(response.error['message'], contains('keywords'));
    });

    test('refuse un mot-clé trop long', () async {
      final Answer response = await api.prepare(
        metadata: <String, Object?>{
          'keywords': <String>['x' * 51],
        },
      );

      expect(response.statusCode, 400);
      expect(response.error['message'], contains('keywords'));
    });

    test('refuse une quatrième catégorie', () async {
      final Answer response = await api.prepare(
        metadata: <String, Object?>{
          'categories': <String>['un', 'deux', 'trois', 'quatre'],
        },
      );

      expect(response.statusCode, 400);
      expect(response.error['message'], contains('categories'));
    });

    test('refuse un ISBN dont la clé de contrôle est fausse', () async {
      final Answer response = await api.prepare(
        metadata: <String, Object?>{'isbn': '9782264000003'},
      );

      expect(response.statusCode, 400);
      expect(response.error['message'], contains('isbn'));
    });

    test('refuse un caractère qu\'Amazon refuse', () async {
      final Answer response = await api.prepare(
        metadata: <String, Object?>{'title': 'La Falaise\u0000'},
      );

      expect(response.statusCode, 400);
      expect(response.error['message'], contains('title'));
    });

    test('refuse le balisage du résumé', () async {
      final Answer response = await api.prepare(
        metadata: <String, Object?>{'description': '<p>Un roman maritime</p>'},
      );

      expect(response.statusCode, 400);
      expect(response.error['message'], contains('description'));
    });

    test('refuse un titre absent', () async {
      final Answer response = await api.send(
        'POST',
        '/v1/publishing/kdp',
        body: <String, Object?>{
          'project_id': api.projectId,
          'author': 'Camille Rivière',
        },
      );

      expect(response.statusCode, 400);
      expect(response.error['message'], contains('title'));
    });
  });

  group('contrôle de soumission', () {
    late KdpApi api;

    setUp(() async {
      api = await KdpApi.start();
    });

    tearDown(() async {
      await api.dispose();
    });

    test('signale un texte trop court', () async {
      final Answer created = await api.prepare();

      expect(created.statusCode, 201);
      expect(created.issueCodes, contains('text_too_short'));
      expect(created.data['status'], 'blocked');
      expect(created.data['word_count'], greaterThan(0));
    });

    test('signale un ISBN manquant pour l\'édition imprimée', () async {
      final Answer created = await api.send(
        'POST',
        '/v1/publishing/kdp',
        body: <String, Object?>{
          'project_id': api.projectId,
          'title': 'La Falaise',
          'author': 'Camille Rivière',
          'description': 'Un roman maritime.',
          'keywords': <String>['roman'],
          'categories': <String>['Romans français'],
        },
      );

      expect(created.issueCodes, contains('isbn_missing'));
    });

    test('chaque problème nomme ce qu\'il faut corriger', () async {
      final Answer created = await api.prepare();

      final List<Object?> issues = created.data['issues']! as List<Object?>;
      for (final Object? issue in issues) {
        final Map<String, dynamic> problem = issue! as Map<String, dynamic>;
        expect(problem['field'], isNotEmpty);
        expect(problem['message'], isNotEmpty);
        expect(problem['severity'], isNotEmpty);
      }
    });

    test('signale un PDF d\'impression trop court', () async {
      final Answer created = await api.prepare();

      expect(created.issueCodes, contains('pdf_too_few_pages'));
      expect(created.data['page_count'], lessThan(24));
    });

    test(
      'un livre complet passe le contrôle',
      () async {
        final KdpApi long = await KdpApi.start(words: 20000);

        final Answer created = await long.prepare();

        expect(created.statusCode, 201);
        expect(created.data['word_count'], greaterThanOrEqualTo(5000));
        expect(created.data['page_count'], greaterThanOrEqualTo(24));
        expect(created.issueCodes, isNot(contains('text_too_short')));
        expect(created.issueCodes, isNot(contains('pdf_too_few_pages')));
        expect(created.data['status'], 'ready');
        await long.dispose();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('base SQLite', () {
    late SqliteDatabase database;
    late KdpApi api;

    setUp(() async {
      database = await SqliteDatabase.openInMemory();
      await _applyMigrations(database);
      final InMemoryObjectStorage storage = InMemoryObjectStorage();
      final SqliteKdpDatabase kdp = SqliteKdpDatabase(
        database,
        planLookup: _planReader('pro'),
        artefacts: storage,
      );
      await _seed(database);
      final KdpApi started = KdpApi._(
        KdpApi._handlerOf(kdp),
        storage,
        () async {},
      );
      started.projectId = 'projet-1';
      api = started;
    });

    tearDown(() async {
      await database.close();
    });

    test('applique la migration et garde la publication', () async {
      final Answer created = await api.prepare();

      expect(created.statusCode, 201);
      expect(created.data['title'], 'La Falaise');

      final Answer listed = await api.send('GET', '/v1/publishing/kdp');
      expect(listed.items, hasLength(1));
      final Map<String, dynamic> publication =
          listed.items.first! as Map<String, dynamic>;
      expect(publication['isbn'], '9782264000002');
      expect(publication['keywords'], <String>[
        'roman maritime',
        'falaise',
        'tempête',
      ]);
      expect(publication['categories'], <String>[
        'Romans français',
        'Littérature maritime',
      ]);
      expect(publication['issues'], isNotEmpty);
    });
  });
}

/// Applique les migrations utiles au test à [database].
Future<void> _applyMigrations(SqliteDatabase database) async {
  const List<String> files = <String>[
    'db/migrations/sqlite/0001_projects.sql',
    'db/migrations/sqlite/0002_project_members.sql',
    'db/migrations/sqlite/0003_sync_ops.sql',
    'db/migrations/sqlite/0013_kdp_publications.sql',
  ];
  const SqlStatementSplitter splitter = SqlStatementSplitter();
  for (final String file in files) {
    final String script = await File(file).readAsString();
    await database.run(() {
      for (final String statement in splitter.split(script)) {
        database.connection.execute(statement);
      }
    });
  }
}

/// Peuple la base SQLite d'un projet et de son manuscrit.
Future<void> _seed(SqliteDatabase database) async {
  await database.run(() {
    database.connection.execute(
      'INSERT INTO projects (id, owner_id, title, synopsis, status, language, '
      'order_key, is_public, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        'projet-1',
        'author-1',
        'La Falaise',
        'Un roman.',
        ManuscriptStatus.draft.name,
        'fr-FR',
        '5',
        0,
        0,
        0,
      ],
    );
  });
  final SqliteSyncStore sync = SqliteSyncStore(database);
  await sync.append(
    projectId: 'projet-1',
    operations: _operations('projet-1', 12),
  );
}
