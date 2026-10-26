import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_api/src/auth/auth_middleware.dart';
import 'package:limpid_api/src/config/app_config.dart';
import 'package:limpid_api/src/db/in_memory_kdp_database.dart';
import 'package:limpid_api/src/db/in_memory_kdp_deposit_store.dart';
import 'package:limpid_api/src/db/kdp_database.dart';
import 'package:limpid_api/src/db/kdp_deposit_record.dart';
import 'package:limpid_api/src/db/kdp_deposit_store.dart';
import 'package:limpid_api/src/db/kdp_record.dart';
import 'package:limpid_api/src/logging/logger.dart';
import 'package:limpid_api/src/middleware/error_handler.dart';
import 'package:limpid_api/src/routes/kdp_publishing_routes.dart';
import 'package:limpid_api/src/services/amazon_kdp_gateway.dart';
import 'package:limpid_api/src/services/kdp_gateway.dart';
import 'package:limpid_api/src/services/kdp_publishing_service.dart';
import 'package:limpid_api/src/storage/object_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

/// La réponse décodée de l'API de dépôt.
final class Answer {
  /// Crée une réponse décodée.
  const Answer(this.statusCode, this.body);

  /// Le code de statut HTTP.
  final int statusCode;

  /// Le corps JSON de la réponse.
  final Map<String, dynamic> body;

  /// La charge utile de la réponse.
  Map<String, dynamic> get data => body['data']! as Map<String, dynamic>;

  /// L'erreur de la réponse.
  Map<String, dynamic> get error => body['error']! as Map<String, dynamic>;

  /// Les détails de l'erreur.
  Map<String, dynamic> get details => error['details']! as Map<String, dynamic>;

  /// Les codes des problèmes portés par la réponse.
  List<String> get issueCodes {
    final List<Object?> issues = _issuesOf(body);
    return <String>[
      for (final Object? issue in issues)
        (issue! as Map<String, dynamic>)['code']! as String,
    ];
  }

  /// Les problèmes portés par la réponse, dans l'enveloppe ou dans les
  /// détails de l'erreur.
  static List<Object?> _issuesOf(Map<String, dynamic> body) {
    final Object? data = body['data'];
    if (data is Map<String, dynamic>) {
      final Object? issues = data['issues'];
      if (issues is List) return issues;
    }
    final Object? error = body['error'];
    if (error is Map<String, dynamic>) {
      final Object? details = error['details'];
      if (details is Map<String, dynamic>) {
        final Object? issues = details['issues'];
        if (issues is List) return issues;
      }
    }
    return const <Object?>[];
  }
}

/// Une passerelle d'Amazon doublée, qui rend les verdicts scriptés.
final class FakeKdpGateway implements KdpGateway {
  /// Crée une passerelle qui rend les verdicts de [outcomes], dans l'ordre.
  FakeKdpGateway([List<KdpSubmissionOutcome>? outcomes])
    : outcomes = outcomes ?? <KdpSubmissionOutcome>[];

  /// Les verdicts qui restent à rendre.
  final List<KdpSubmissionOutcome> outcomes;

  /// Les demandes reçues, pour les assertions.
  final List<KdpSubmissionRequest> requests = <KdpSubmissionRequest>[];

  @override
  Future<KdpSubmissionOutcome> submit(KdpSubmissionRequest request) async {
    requests.add(request);
    if (outcomes.isEmpty) {
      return const KdpSubmissionAccepted('amazon-1');
    }
    return outcomes.removeAt(0);
  }
}

/// L'API de dépôt, servie en mémoire.
final class KdpPublishingApi {
  KdpPublishingApi._(
    this._handler,
    this.gateway,
    this.publications,
    this.deposits,
    this.storage,
  );

  final Handler _handler;

  /// La passerelle d'Amazon qui sert l'API.
  final KdpGateway gateway;

  /// Les publications préparées.
  final KdpDatabase publications;

  /// La trace des dépôts.
  final KdpDepositStore deposits;

  /// Le stockage qui porte les fichiers déposés.
  final InMemoryObjectStorage storage;

  /// L'identifiant de la publication préparée.
  static const String publicationId = 'publication-1';

  /// Démarre l'API avec une publication déjà préparée.
  ///
  /// [status] et [issues] décrivent le résultat du contrôle de soumission :
  /// une publication bloquée n'est jamais déposée. [gateway] est la porte
  /// de sortie vers Amazon : la suite la double pour contrôler les verdicts.
  static Future<KdpPublishingApi> start({
    KdpGateway? gateway,
    bool configured = true,
    KdpPublicationStatus status = KdpPublicationStatus.ready,
    List<KdpIssue> issues = const <KdpIssue>[],
  }) async {
    final InMemoryObjectStorage storage = InMemoryObjectStorage();
    final KdpDatabase publications = InMemoryKdpDatabase(artefacts: storage);
    final KdpDepositStore deposits = InMemoryKdpDepositStore();
    await publications.recordPublication(
      _publication(status: status, issues: issues),
    );

    final KdpGateway resolved = gateway ?? FakeKdpGateway();
    final KdpPublishingService service = KdpPublishingService(
      publications: publications,
      deposits: deposits,
      gateway: resolved,
    );

    final Router router = Router();
    registerKdpPublishingRoutes(
      router,
      service,
      _config(configured: configured),
    );
    final Logger logger = Logger(
      level: LogLevel.warning,
      sink: (String line) {},
    );
    return KdpPublishingApi._(
      errorHandlerMiddleware(logger: logger)(router.call),
      resolved,
      publications,
      deposits,
      storage,
    );
  }

  /// Envoie une requête authentifiée et décode la réponse.
  Future<Answer> send(
    String method,
    String path, {
    Map<String, Object?>? body,
    String userId = 'author-1',
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

  /// Dépose le dossier préparé.
  Future<Answer> deposit({
    String userId = 'author-1',
    String publicationId = KdpPublishingApi.publicationId,
  }) {
    return send(
      'POST',
      '/v1/publishing/kdp/deposits',
      userId: userId,
      body: <String, Object?>{'publication_id': publicationId},
    );
  }

  /// Réconcilie un dépôt dont l'issue est inconnue.
  Future<Answer> reconcile(
    String depositId, {
    required Map<String, Object?> body,
    String userId = 'author-1',
  }) {
    return send(
      'POST',
      '/v1/publishing/kdp/deposits/$depositId/reconciliation',
      userId: userId,
      body: body,
    );
  }

  /// La configuration du serveur de test.
  ///
  /// Les identifiants Amazon ne sont là que quand la distribution est
  /// configurée : la route refuse proprement quand ils manquent.
  static AppConfig _config({required bool configured}) {
    return AppConfig.fromEnvironment(<String, String>{
      'PORT': '0',
      'SUPABASE_URL': 'https://project.test',
      'LOG_LEVEL': 'warning',
      if (configured) 'AMAZON_KDP_CLIENT_ID': 'client-id',
      if (configured) 'AMAZON_KDP_CLIENT_SECRET': 'client-secret',
      if (configured) 'AMAZON_KDP_REFRESH_TOKEN': 'refresh-token',
    });
  }
}

/// La publication préparée que le dépôt reprend.
KdpPublication _publication({
  KdpPublicationStatus status = KdpPublicationStatus.ready,
  List<KdpIssue> issues = const <KdpIssue>[],
}) {
  return KdpPublication(
    id: KdpPublishingApi.publicationId,
    projectId: 'project-1',
    userId: 'author-1',
    title: 'La Falaise',
    author: 'Camille Rivière',
    description: 'Un roman maritime sur une côte battue par les vents.',
    keywords: const <String>['roman maritime', 'falaise'],
    categories: const <String>['Romans français'],
    issues: issues,
    isbn: '9782264000002',
    language: 'fr-FR',
    publisher: 'Éditions du vent',
    status: status,
    wordCount: 12000,
    pageCount: 240,
    epubKey: 'exports/project-1/kdp/publication-1/livre.epub',
    pdfKey: 'exports/project-1/kdp/publication-1/livre.pdf',
    epubBytes: 2048,
    pdfBytes: 4096,
    manuscriptVersion: '2026-10-25T10:00:00.000Z',
    createdAt: DateTime.utc(2026, 10, 25),
  );
}

/// Le motif d'une issue incertaine, écrit pour l'auteur.
const String unknownReason =
    "Amazon n'a pas répondu à temps. L'issue du dépôt est incertaine : "
    'Amazon a peut-être reçu le dossier.';

void main() {
  group('dépôt du dossier préparé', () {
    test('dépose le dossier et rend la trace du dépôt', () async {
      final KdpPublishingApi api = await KdpPublishingApi.start();

      final Answer answer = await api.deposit();

      expect(answer.statusCode, 200);
      expect(answer.data['status'], 'submitted');
      expect(answer.data['amazon_submission_id'], 'amazon-1');
      expect(answer.data['publication_id'], KdpPublishingApi.publicationId);
      expect(answer.data['attempts'], 1);
      expect(answer.data['created_at'], isNotEmpty);
      expect(answer.data['updated_at'], isNotEmpty);
    });

    test('envoie à Amazon le dossier et ses deux fichiers', () async {
      final FakeKdpGateway gateway = FakeKdpGateway();
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
      );

      await api.deposit();

      final KdpSubmissionRequest request = gateway.requests.single;
      expect(request.title, 'La Falaise');
      expect(request.author, 'Camille Rivière');
      expect(request.isbn, '9782264000002');
      expect(request.keywords, contains('falaise'));
      expect(request.epubUrl, contains('livre.epub'));
      expect(request.pdfUrl, contains('livre.pdf'));
      expect(request.depositId, isNotEmpty);
    });

    test('rend le refus d\'Amazon comme une liste de problèmes', () async {
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: FakeKdpGateway(<KdpSubmissionOutcome>[
          KdpSubmissionRefused(<KdpIssue>[
            const KdpIssue(
              code: 'isbn_already_in_use',
              field: 'isbn',
              message: "L'ISBN indiqué est déjà utilisé par un autre ouvrage.",
            ),
          ]),
        ]),
      );

      final Answer answer = await api.deposit();

      expect(answer.statusCode, 200);
      expect(answer.data['status'], 'rejected');
      expect(answer.issueCodes, <String>['isbn_already_in_use']);
      final List<Object?> issues = answer.data['issues']! as List<Object?>;
      final Map<String, dynamic> issue = issues.single! as Map<String, dynamic>;
      expect(issue['field'], 'isbn');
      expect(issue['message'], isNotEmpty);
      expect(issue['severity'], 'blocking');
    });

    test('rejoue un dépôt qui a échoué', () async {
      final FakeKdpGateway gateway = FakeKdpGateway(<KdpSubmissionOutcome>[
        const KdpSubmissionUnavailable(
          "Amazon n'a pas répondu à temps. Le dossier n'a pas été transmis.",
        ),
        const KdpSubmissionAccepted('amazon-2'),
      ]);
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
      );

      final Answer failed = await api.deposit();
      expect(failed.statusCode, 503);
      expect(failed.error['code'], 'service_unavailable');
      expect(failed.details['deposit_id'], isNotEmpty);

      final Answer resumed = await api.deposit();
      expect(resumed.statusCode, 200);
      expect(resumed.data['status'], 'submitted');
      expect(resumed.data['attempts'], 2);
      expect(resumed.data['id'], failed.details['deposit_id']);
      expect(gateway.requests, hasLength(2));
      expect(gateway.requests.first.depositId, gateway.requests.last.depositId);
    });

    test('ne dépose jamais deux fois un dossier accepté', () async {
      final FakeKdpGateway gateway = FakeKdpGateway();
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
      );

      final Answer first = await api.deposit();
      final Answer second = await api.deposit();

      expect(first.statusCode, 200);
      expect(second.statusCode, 200);
      expect(second.data['status'], 'submitted');
      expect(second.data['id'], first.data['id']);
      expect(second.data['amazon_submission_id'], 'amazon-1');
      expect(gateway.requests, hasLength(1));
    });

    test('ne reprend pas deux fois un dossier en échec', () async {
      final FakeKdpGateway gateway = FakeKdpGateway(<KdpSubmissionOutcome>[
        const KdpSubmissionUnavailable(
          "Amazon n'a pas répondu à temps. Le dossier n'a pas été transmis.",
        ),
        const KdpSubmissionAccepted('amazon-2'),
      ]);
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
      );
      final Answer failed = await api.deposit();
      expect(failed.statusCode, 503);

      final List<Answer> answers = await Future.wait(<Future<Answer>>[
        api.deposit(),
        api.deposit(),
      ]);

      // Une seule reprise part chez Amazon : l'autre demande refuse, elle
      // ne renvoie pas le dossier une seconde fois.
      expect(gateway.requests, hasLength(2));
      for (final Answer answer in answers) {
        expect(answer.statusCode, isNot(503));
      }
    });

    test('refuse de relancer un dépôt laissé en attente', () async {
      final FakeKdpGateway gateway = FakeKdpGateway();
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
      );
      await api.deposits.insertDeposit(
        KdpDeposit(
          id: 'deposit-pending',
          publicationId: KdpPublishingApi.publicationId,
          userId: 'author-1',
          status: KdpDepositStatus.pending,
          issues: const <KdpIssue>[],
          attempts: 1,
          createdAt: DateTime.utc(2026, 10, 25),
          updatedAt: DateTime.utc(2026, 10, 25),
        ),
      );

      final Answer answer = await api.deposit();

      // Le dossier est peut-être déjà chez Amazon : le renvoyer créerait
      // une seconde fiche KDP.
      expect(answer.statusCode, 409);
      expect(answer.error['code'], 'conflict');
      expect(answer.details['status'], 'pending');
      expect(answer.details['requires_reconciliation'], isTrue);
      expect(gateway.requests, isEmpty);
    });

    test(
      'ne dépose pas deux fois un dossier demandé deux fois à la fois',
      () async {
        final FakeKdpGateway gateway = FakeKdpGateway();
        final KdpPublishingApi api = await KdpPublishingApi.start(
          gateway: gateway,
        );

        final List<Answer> answers = await Future.wait(<Future<Answer>>[
          api.deposit(),
          api.deposit(),
        ]);

        // Un seul des deux appels part : l'autre refuse, le dossier n'est
        // pas envoyé deux fois.
        expect(
          answers.where((Answer answer) => answer.statusCode == 200),
          hasLength(1),
        );
        expect(
          answers.where((Answer answer) => answer.statusCode == 409),
          hasLength(1),
        );
        expect(gateway.requests, hasLength(1));
      },
    );

    test('ne dépose pas un dossier bloqué par le contrôle', () async {
      final FakeKdpGateway gateway = FakeKdpGateway();
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
        status: KdpPublicationStatus.blocked,
        issues: <KdpIssue>[
          const KdpIssue(
            code: 'isbn_missing',
            field: 'isbn',
            message: "L'édition imprimée exige un ISBN.",
          ),
        ],
      );

      final Answer answer = await api.deposit();

      expect(answer.statusCode, 409);
      expect(answer.error['code'], 'conflict');
      expect(answer.issueCodes, <String>['isbn_missing']);
      expect(gateway.requests, isEmpty);
    });

    test('refuse une publication inconnue', () async {
      final FakeKdpGateway gateway = FakeKdpGateway();
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
      );

      final Answer answer = await api.deposit(publicationId: 'inconnue');

      expect(answer.statusCode, 404);
      expect(answer.error['code'], 'not_found');
      expect(gateway.requests, isEmpty);
    });

    test('ne montre pas le dépôt à un autre compte', () async {
      final KdpPublishingApi api = await KdpPublishingApi.start();
      final Answer created = await api.deposit();
      final String depositId = created.data['id']! as String;

      final Answer answer = await api.send(
        'GET',
        '/v1/publishing/kdp/deposits/$depositId',
        userId: 'etranger',
      );

      expect(answer.statusCode, 404);
      expect(answer.error['code'], 'not_found');
    });

    test('relit le dépôt après coup', () async {
      final KdpPublishingApi api = await KdpPublishingApi.start();
      final Answer created = await api.deposit();
      final String depositId = created.data['id']! as String;

      final Answer answer = await api.send(
        'GET',
        '/v1/publishing/kdp/deposits/$depositId',
      );

      expect(answer.statusCode, 200);
      expect(answer.data['id'], depositId);
      expect(answer.data['status'], 'submitted');
    });
  });

  group('issue inconnue', () {
    test(
      'un délai dépassé ne redonne pas le droit de renvoyer le dossier',
      () async {
        final List<http.Request> sent = <http.Request>[];
        final AmazonKdpGateway gateway = AmazonKdpGateway(
          clientId: 'client-id',
          clientSecret: 'client-secret',
          refreshToken: 'refresh-token',
          budget: const Duration(milliseconds: 100),
          client: MockClient((http.Request request) async {
            sent.add(request);
            if (request.url == Uri.parse(AmazonKdpGateway.tokenUrl)) {
              return http.Response(
                jsonEncode(<String, Object?>{
                  'access_token': 'jeton-1',
                  'expires_in': 3600,
                }),
                200,
              );
            }
            // Amazon ne répond jamais : le dossier est parti, l'issue n'est
            // pas connue.
            return Completer<http.Response>().future;
          }),
        );
        final KdpPublishingApi api = await KdpPublishingApi.start(
          gateway: gateway,
        );

        final Answer first = await api.deposit();

        expect(first.statusCode, 409);
        expect(first.error['code'], 'conflict');
        expect(first.details['status'], 'unknown');
        expect(first.details['requires_reconciliation'], isTrue);
        expect(first.error['message'], contains('incertaine'));

        final Answer second = await api.deposit();

        // La relance est refusée : le dossier ne repart pas chez Amazon.
        expect(second.statusCode, 409);
        expect(
          sent.where(
            (http.Request request) =>
                request.url == Uri.parse(AmazonKdpGateway.depositUrl),
          ),
          hasLength(1),
        );
      },
    );

    test(
      'un dépôt à l\'issue inconnue refuse la relance automatique',
      () async {
        final FakeKdpGateway gateway = FakeKdpGateway(<KdpSubmissionOutcome>[
          const KdpSubmissionUnknown(unknownReason),
        ]);
        final KdpPublishingApi api = await KdpPublishingApi.start(
          gateway: gateway,
        );

        final Answer answer = await api.deposit();

        expect(answer.statusCode, 409);
        expect(answer.details['requires_reconciliation'], isTrue);
        expect(gateway.requests, hasLength(1));

        final Answer again = await api.deposit();

        expect(again.statusCode, 409);
        expect(gateway.requests, hasLength(1));
      },
    );

    test(
      'la trace d\'un dépôt incertain porte le motif de l\'incertitude',
      () async {
        final KdpPublishingApi api = await KdpPublishingApi.start(
          gateway: FakeKdpGateway(<KdpSubmissionOutcome>[
            const KdpSubmissionUnknown(unknownReason),
          ]),
        );

        await api.deposit();

        final KdpDeposit? deposit = await api.deposits.findDepositByPublication(
          publicationId: KdpPublishingApi.publicationId,
          userId: 'author-1',
        );
        expect(deposit?.status, KdpDepositStatus.unknown);
        expect(deposit?.failureReason, contains('incertaine'));
        expect(deposit?.isResumable, isFalse);
      },
    );
  });

  group('raisons d\'Amazon', () {
    test('un compte bloqué a sa raison dans la trace', () async {
      final AmazonKdpGateway gateway = AmazonKdpGateway(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        refreshToken: 'refresh-token',
        budget: const Duration(seconds: 30),
        client: MockClient((http.Request request) async {
          if (request.url == Uri.parse(AmazonKdpGateway.tokenUrl)) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'access_token': 'jeton-1',
                'expires_in': 3600,
              }),
              200,
            );
          }
          // Amazon refuse la demande : le compte est bloqué.
          return http.Response('{}', 403);
        }),
      );
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
      );

      final Answer answer = await api.deposit();

      expect(answer.statusCode, 503);
      final String message = answer.error['message']! as String;
      expect(message, contains('bloqué'));
      // Relancer ne sert à rien quand le compte est bloqué : le message ne
      // doit pas le dire.
      expect(message.toLowerCase(), isNot(contains('relance')));

      // La trace porte la raison, elle est lisible par l'auteur.
      final KdpDeposit? deposit = await api.deposits.findDepositByPublication(
        publicationId: KdpPublishingApi.publicationId,
        userId: 'author-1',
      );
      expect(deposit?.status, KdpDepositStatus.failed);
      expect(deposit?.failureReason, contains('bloqué'));
    });

    test('un dépôt bridé a sa raison dans la trace', () async {
      final AmazonKdpGateway gateway = AmazonKdpGateway(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        refreshToken: 'refresh-token',
        budget: const Duration(seconds: 30),
        client: MockClient((http.Request request) async {
          if (request.url == Uri.parse(AmazonKdpGateway.tokenUrl)) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'access_token': 'jeton-1',
                'expires_in': 3600,
              }),
              200,
            );
          }
          // Amazon bride les dépôts : le dossier n'est pas parti.
          return http.Response('{}', 429);
        }),
      );
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
      );

      final Answer answer = await api.deposit();

      expect(answer.statusCode, 503);
      final String message = answer.error['message']! as String;
      expect(message, contains('limite'));
      expect(message.toLowerCase(), isNot(contains('relance')));

      final KdpDeposit? deposit = await api.deposits.findDepositByPublication(
        publicationId: KdpPublishingApi.publicationId,
        userId: 'author-1',
      );
      expect(deposit?.failureReason, contains('limite'));
    });

    test('un jeton refusé a sa raison dans la trace', () async {
      final AmazonKdpGateway gateway = AmazonKdpGateway(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        refreshToken: 'refresh-token',
        budget: const Duration(seconds: 30),
        client: MockClient((http.Request request) async {
          // Amazon refuse les identifiants de l'intégration.
          return http.Response('{}', 401);
        }),
      );
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
      );

      final Answer answer = await api.deposit();

      expect(answer.statusCode, 503);
      final String message = answer.error['message']! as String;
      expect(message, contains('identifiants'));
      expect(message.toLowerCase(), isNot(contains('relance')));

      final KdpDeposit? deposit = await api.deposits.findDepositByPublication(
        publicationId: KdpPublishingApi.publicationId,
        userId: 'author-1',
      );
      expect(deposit?.failureReason, contains('identifiants'));
    });
  });

  group('message d\'Amazon', () {
    test('est borné et échappé avant d\'être stocké', () async {
      final AmazonKdpGateway gateway = AmazonKdpGateway(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        refreshToken: 'refresh-token',
        budget: const Duration(seconds: 30),
        client: MockClient((http.Request request) async {
          if (request.url == Uri.parse(AmazonKdpGateway.tokenUrl)) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'access_token': 'jeton-1',
                'expires_in': 3600,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'issues': <Object?>[
                <String, Object?>{
                  'code': 'mystere',
                  'field': 'title',
                  'message': '<script>alert("x")</script>${'a' * 800}',
                },
              ],
            }),
            400,
          );
        }),
      );
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
      );

      final Answer answer = await api.deposit();

      expect(answer.statusCode, 200);
      expect(answer.data['status'], 'rejected');
      final List<Object?> issues = answer.data['issues']! as List<Object?>;
      final Map<String, dynamic> issue = issues.single! as Map<String, dynamic>;
      final String message = issue['message']! as String;

      // Le message stocké est borné, échappé, et ne porte pas la balise.
      expect(message.length, lessThanOrEqualTo(512));
      expect(message, isNot(contains('<')));
      expect(message, contains('&lt;script&gt;'));
    });
  });

  group('réconciliation', () {
    test('l\'auteur déclare que la soumission existe', () async {
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: FakeKdpGateway(<KdpSubmissionOutcome>[
          const KdpSubmissionUnknown(unknownReason),
        ]),
      );
      final Answer failed = await api.deposit();
      final String depositId = failed.details['deposit_id']! as String;

      final Answer answer = await api.reconcile(
        depositId,
        body: <String, Object?>{
          'outcome': 'submitted',
          'amazon_submission_id': 'amazon-42',
        },
      );

      expect(answer.statusCode, 200);
      expect(answer.data['status'], 'submitted');
      expect(answer.data['amazon_submission_id'], 'amazon-42');
      expect(answer.data['failure_reason'], isNull);
    });

    test('l\'auteur déclare qu\'Amazon n\'a rien reçu', () async {
      final FakeKdpGateway gateway = FakeKdpGateway(<KdpSubmissionOutcome>[
        const KdpSubmissionUnknown(unknownReason),
        const KdpSubmissionAccepted('amazon-43'),
      ]);
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
      );
      final Answer failed = await api.deposit();
      final String depositId = failed.details['deposit_id']! as String;

      final Answer reconciled = await api.reconcile(
        depositId,
        body: <String, Object?>{'outcome': 'not_received'},
      );

      expect(reconciled.statusCode, 200);
      expect(reconciled.data['status'], 'failed');
      expect(reconciled.data['failure_reason'], contains('rien reçu'));

      // Le dossier peut repartir : c'est l'auteur qui l'a demandé.
      final Answer resumed = await api.deposit();
      expect(resumed.statusCode, 200);
      expect(resumed.data['status'], 'submitted');
      expect(gateway.requests, hasLength(2));
    });

    test('réconcilie un dépôt laissé en attente', () async {
      final KdpPublishingApi api = await KdpPublishingApi.start();
      await api.deposits.insertDeposit(
        KdpDeposit(
          id: 'deposit-pending',
          publicationId: KdpPublishingApi.publicationId,
          userId: 'author-1',
          status: KdpDepositStatus.pending,
          issues: const <KdpIssue>[],
          attempts: 1,
          createdAt: DateTime.utc(2026, 10, 25),
          updatedAt: DateTime.utc(2026, 10, 25),
        ),
      );

      final Answer answer = await api.reconcile(
        'deposit-pending',
        body: <String, Object?>{
          'outcome': 'submitted',
          'amazon_submission_id': 'amazon-42',
        },
      );

      expect(answer.statusCode, 200);
      expect(answer.data['status'], 'submitted');
      expect(answer.data['amazon_submission_id'], 'amazon-42');
    });

    test('refuse une seconde réconciliation du même dépôt', () async {
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: FakeKdpGateway(<KdpSubmissionOutcome>[
          const KdpSubmissionUnknown(unknownReason),
        ]),
      );
      final Answer failed = await api.deposit();
      final String depositId = failed.details['deposit_id']! as String;

      final Answer first = await api.reconcile(
        depositId,
        body: <String, Object?>{
          'outcome': 'submitted',
          'amazon_submission_id': 'amazon-42',
        },
      );
      expect(first.statusCode, 200);

      // La trace a changé : une déclaration contraire ne s'applique pas.
      final Answer second = await api.reconcile(
        depositId,
        body: <String, Object?>{'outcome': 'not_received'},
      );
      expect(second.statusCode, 409);
      expect(second.error['code'], 'conflict');

      final KdpDeposit? deposit = await api.deposits.findDeposit(
        depositId: depositId,
        userId: 'author-1',
      );
      expect(deposit?.status, KdpDepositStatus.submitted);
    });

    test('refuse de réconcilier un dépôt sans issue incertaine', () async {
      final KdpPublishingApi api = await KdpPublishingApi.start();
      final Answer created = await api.deposit();
      final String depositId = created.data['id']! as String;

      final Answer answer = await api.reconcile(
        depositId,
        body: <String, Object?>{'outcome': 'not_received'},
      );

      expect(answer.statusCode, 409);
      expect(answer.error['code'], 'conflict');
    });

    test('refuse une réconciliation sans déclaration', () async {
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: FakeKdpGateway(<KdpSubmissionOutcome>[
          const KdpSubmissionUnknown(unknownReason),
        ]),
      );
      final Answer failed = await api.deposit();
      final String depositId = failed.details['deposit_id']! as String;

      final Answer answer = await api.reconcile(
        depositId,
        body: <String, Object?>{'outcome': 'peut-etre'},
      );

      expect(answer.statusCode, 400);
      expect(answer.error['code'], 'validation_failed');
    });

    test('ne montre pas un dépôt à un autre compte', () async {
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: FakeKdpGateway(<KdpSubmissionOutcome>[
          const KdpSubmissionUnknown(unknownReason),
        ]),
      );
      final Answer failed = await api.deposit();
      final String depositId = failed.details['deposit_id']! as String;

      final Answer answer = await api.reconcile(
        depositId,
        userId: 'etranger',
        body: <String, Object?>{'outcome': 'not_received'},
      );

      expect(answer.statusCode, 404);
      expect(answer.error['code'], 'not_found');
    });
  });

  group('configuration absente', () {
    test('refuse proprement le dépôt', () async {
      final FakeKdpGateway gateway = FakeKdpGateway();
      final KdpPublishingApi api = await KdpPublishingApi.start(
        gateway: gateway,
        configured: false,
      );

      final Answer answer = await api.deposit();

      expect(answer.statusCode, 503);
      expect(answer.error['code'], 'service_unavailable');
      expect(answer.error['message'], contains('Amazon'));
      expect(gateway.requests, isEmpty);
    });
  });
}
