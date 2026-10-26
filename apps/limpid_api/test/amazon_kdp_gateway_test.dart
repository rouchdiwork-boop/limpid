import 'dart:async';
import 'dart:convert';
import 'dart:mirrors';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_api/src/db/kdp_record.dart';
import 'package:limpid_api/src/services/amazon_kdp_gateway.dart';
import 'package:limpid_api/src/services/kdp_gateway.dart';
import 'package:test/test.dart';

/// La réponse du service d'autorisation d'Amazon.
http.Response _tokenResponse({String token = 'jeton-1', int expiresIn = 3600}) {
  return http.Response(
    jsonEncode(<String, Object?>{
      'access_token': token,
      'expires_in': expiresIn,
      'token_type': 'bearer',
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

/// La réponse d'acceptation d'Amazon.
http.Response _acceptedResponse({String submissionId = 'amazon-42'}) {
  return http.Response(
    jsonEncode(<String, Object?>{'submission_id': submissionId}),
    201,
  );
}

/// La demande de dépôt, pour les tests du client Amazon.
KdpSubmissionRequest _submissionRequest() {
  return const KdpSubmissionRequest(
    depositId: 'deposit-1',
    title: 'La Falaise',
    author: 'Camille Rivière',
    description: 'Un roman maritime.',
    keywords: <String>['roman maritime'],
    categories: <String>['Romans français'],
    isbn: '9782264000002',
    language: 'fr-FR',
    publisher: 'Éditions du vent',
    epubUrl: 'https://storage.test/livre.epub',
    pdfUrl: 'https://storage.test/livre.pdf',
  );
}

/// La passerelle de dépôt, avec un client qui répond à la place d'Amazon.
AmazonKdpGateway _gateway({
  required Future<http.Response> Function(http.Request request) handler,
  Duration budget = const Duration(seconds: 30),
  DateTime Function()? clock,
}) {
  return AmazonKdpGateway(
    clientId: 'client-id',
    clientSecret: 'client-secret',
    refreshToken: 'refresh-token',
    budget: budget,
    clock: clock,
    client: MockClient(handler),
  );
}

/// La réponse d'Amazon pour le chemin donné.
bool _isToken(http.Request request) =>
    request.url == Uri.parse(AmazonKdpGateway.tokenUrl);

/// La réponse d'Amazon pour le chemin du dépôt.
bool _isDeposit(http.Request request) =>
    request.url == Uri.parse(AmazonKdpGateway.depositUrl);

void main() {
  group('client Amazon', () {
    test('demande un jeton et le porte dans l\'en-tête', () async {
      final List<http.Request> sent = <http.Request>[];
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          sent.add(request);
          if (_isToken(request)) return _tokenResponse();
          return _acceptedResponse();
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      expect(outcome, isA<KdpSubmissionAccepted>());
      expect((outcome as KdpSubmissionAccepted).submissionId, 'amazon-42');
      expect(sent, hasLength(2));

      // Le jeton d'accès ne voyage que dans l'en-tête d'autorisation.
      expect(sent[1].headers['authorization'], 'Bearer jeton-1');
      expect(sent[1].url.query, isEmpty);
      expect(sent[1].url.toString(), AmazonKdpGateway.depositUrl);

      // Le secret du client ne voyage que dans le corps de la demande
      // d'autorisation, et jamais dans une adresse.
      expect(sent[0].bodyFields['client_secret'], 'client-secret');
      expect(sent[0].bodyFields['grant_type'], 'refresh_token');
      expect(sent[0].url.query, isEmpty);
    });

    test('n\'envoie aucun en-tête d\'idempotence à Amazon', () async {
      final List<http.Request> sent = <http.Request>[];
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          sent.add(request);
          if (_isToken(request)) return _tokenResponse();
          return _acceptedResponse();
        },
      );

      await gateway.submit(_submissionRequest());

      // Amazon n'honore pas d'en-tête d'idempotence : en envoyer un
      // laisserait croire à une protection qui n'existe pas.
      expect(
        sent.where(_isDeposit).single.headers.containsKey('idempotency-key'),
        isFalse,
      );
    });

    test('renouvelle le jeton quand il a expiré', () async {
      int tokens = 0;
      DateTime now = DateTime.utc(2026, 10, 25);
      final AmazonKdpGateway gateway = _gateway(
        clock: () => now,
        handler: (http.Request request) async {
          if (_isToken(request)) {
            tokens++;
            return _tokenResponse(token: 'jeton-$tokens');
          }
          return _acceptedResponse();
        },
      );

      await gateway.submit(_submissionRequest());
      now = now.add(const Duration(hours: 2));
      await gateway.submit(_submissionRequest());

      expect(tokens, 2);
    });

    test(
      'ne redemande pas un jeton quand Amazon annonce une durée courte',
      () async {
        int tokens = 0;
        final AmazonKdpGateway gateway = _gateway(
          handler: (http.Request request) async {
            if (_isToken(request)) {
              tokens++;
              return _tokenResponse(expiresIn: 30);
            }
            return _acceptedResponse();
          },
        );

        await gateway.submit(_submissionRequest());
        await gateway.submit(_submissionRequest());

        // La durée annoncée est ramenée à la durée minimale : un jeton déjà
        // expiré ne ferait redemander un jeton à chaque dépôt.
        expect(tokens, 1);
      },
    );

    test('renouvelle le jeton quand Amazon le refuse', () async {
      int tokens = 0;
      int deposits = 0;
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          if (_isToken(request)) {
            tokens++;
            return _tokenResponse(token: 'jeton-$tokens');
          }
          deposits++;
          if (deposits == 1) return http.Response('{}', 401);
          return _acceptedResponse();
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      expect(outcome, isA<KdpSubmissionAccepted>());
      expect(tokens, 2);
      expect(deposits, 2);
    });

    test('rend le refus d\'Amazon comme une liste de problèmes', () async {
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          if (_isToken(request)) return _tokenResponse();
          return http.Response(
            jsonEncode(<String, Object?>{
              'issues': <Object?>[
                <String, Object?>{
                  'code': 'isbn_already_in_use',
                  'field': 'isbn',
                  'message': 'This ISBN is already in use.',
                  'severity': 'blocking',
                },
              ],
            }),
            422,
          );
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      expect(outcome, isA<KdpSubmissionRefused>());
      final List<KdpIssue> issues = (outcome as KdpSubmissionRefused).issues;
      expect(issues, hasLength(1));
      expect(issues.single.code, 'isbn_already_in_use');
      expect(issues.single.field, 'isbn');
      expect(issues.single.isBlocking, isTrue);
      expect(issues.single.message, contains('ISBN'));
    });

    test('borne le message d\'Amazon avant de le stocker', () async {
      final String huge = 'x' * 5000;
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          if (_isToken(request)) return _tokenResponse();
          return http.Response(
            jsonEncode(<String, Object?>{
              'issues': <Object?>[
                <String, Object?>{
                  'code': 'mystere',
                  'field': 'isbn',
                  'message': huge,
                },
              ],
            }),
            422,
          );
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      final KdpIssue issue = (outcome as KdpSubmissionRefused).issues.single;
      // Le message stocké, préfixe compris, ne dépasse jamais 512
      // caractères : la trace du dépôt ne peut pas être gonflée par une
      // réponse d'Amazon.
      expect(issue.message.length, lessThanOrEqualTo(512));
      expect(issue.message, contains('…'));
      expect(issue.message, isNot(contains(huge)));
    });

    test('échappe le message d\'Amazon avant de le stocker', () async {
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          if (_isToken(request)) return _tokenResponse();
          return http.Response(
            jsonEncode(<String, Object?>{
              'issues': <Object?>[
                <String, Object?>{
                  'code': 'mystere',
                  'field': 'isbn',
                  'message': '<script>alert("x")</script>',
                },
              ],
            }),
            422,
          );
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      final KdpIssue issue = (outcome as KdpSubmissionRefused).issues.single;
      expect(issue.message, isNot(contains('<script>')));
      expect(issue.message, contains('&lt;script&gt;'));
    });
  });

  group('issue inconnue', () {
    test('rend un délai dépassé du dépôt comme une issue inconnue', () async {
      final AmazonKdpGateway gateway = _gateway(
        budget: const Duration(milliseconds: 50),
        handler: (http.Request request) async {
          if (_isToken(request)) return _tokenResponse();
          return Completer<http.Response>().future;
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      // Le dossier est parti : Amazon l'a peut-être reçu.
      expect(outcome, isA<KdpSubmissionUnknown>());
      expect((outcome as KdpSubmissionUnknown).reason, contains('incertaine'));
    });

    test('rend une panne réseau du dépôt comme une issue inconnue', () async {
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          if (_isToken(request)) return _tokenResponse();
          throw http.ClientException('réseau coupé');
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      expect(outcome, isA<KdpSubmissionUnknown>());
    });

    test(
      'rend une réponse illisible d\'Amazon comme une issue inconnue',
      () async {
        final AmazonKdpGateway gateway = _gateway(
          handler: (http.Request request) async {
            if (_isToken(request)) return _tokenResponse();
            return http.Response('pas du json', 201);
          },
        );

        final KdpSubmissionOutcome outcome = await gateway.submit(
          _submissionRequest(),
        );

        expect(outcome, isA<KdpSubmissionUnknown>());
      },
    );

    test('rend un délai dépassé du jeton comme un échec', () async {
      final AmazonKdpGateway gateway = _gateway(
        budget: const Duration(milliseconds: 50),
        handler: (http.Request request) async {
          return Completer<http.Response>().future;
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      // Le dossier n'est jamais parti : il peut être relancé.
      expect(outcome, isA<KdpSubmissionUnavailable>());
      expect(
        (outcome as KdpSubmissionUnavailable).reason,
        contains("n'a pas été transmis"),
      );
    });

    test('rend une panne réseau du jeton comme un échec', () async {
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          throw http.ClientException('réseau coupé');
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      expect(outcome, isA<KdpSubmissionUnavailable>());
      expect(
        (outcome as KdpSubmissionUnavailable).reason,
        contains("n'a pas été transmis"),
      );
    });
  });

  group('budget de la requête', () {
    test(
      'le second appel ne part pas quand le premier a mangé le budget',
      () async {
        DateTime now = DateTime.utc(2026, 10, 25);
        final List<http.Request> sent = <http.Request>[];
        final AmazonKdpGateway gateway = _gateway(
          budget: const Duration(seconds: 30),
          clock: () => now,
          handler: (http.Request request) async {
            sent.add(request);
            if (_isToken(request)) {
              // Le jeton a pris tout le budget : il ne reste plus de temps.
              now = now.add(const Duration(seconds: 31));
              return _tokenResponse();
            }
            return _acceptedResponse();
          },
        );

        final KdpSubmissionOutcome outcome = await gateway.submit(
          _submissionRequest(),
        );

        expect(outcome, isA<KdpSubmissionUnavailable>());
        expect(sent, hasLength(1));
        expect(sent.single.url.toString(), AmazonKdpGateway.tokenUrl);
      },
    );

    test('le second appel reçoit le temps qui reste', () async {
      DateTime now = DateTime.utc(2026, 10, 25);
      final Stopwatch watch = Stopwatch()..start();
      final AmazonKdpGateway gateway = _gateway(
        budget: const Duration(seconds: 2),
        clock: () => now,
        handler: (http.Request request) async {
          if (_isToken(request)) {
            now = now.add(const Duration(milliseconds: 1500));
            return _tokenResponse();
          }
          return Completer<http.Response>().future;
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );
      watch.stop();

      // Le dépôt n'a reçu que les 500 ms qui restaient : il n'a pas
      // attendu les 2 s du budget.
      expect(outcome, isA<KdpSubmissionUnknown>());
      expect(watch.elapsedMilliseconds, lessThan(1500));
    });
  });

  group('statuts d\'Amazon', () {
    test('rend un 401 avec la raison des identifiants', () async {
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          if (_isToken(request)) return _tokenResponse();
          return http.Response('{}', 401);
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      expect(outcome, isA<KdpSubmissionUnavailable>());
      final String reason = (outcome as KdpSubmissionUnavailable).reason;
      expect(reason, contains('identifiants'));
      expect(reason, isNot(contains('relance')));
    });

    test('rend un 403 avec la raison du compte bloqué', () async {
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          if (_isToken(request)) return _tokenResponse();
          return http.Response('{}', 403);
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      expect(outcome, isA<KdpSubmissionUnavailable>());
      final String reason = (outcome as KdpSubmissionUnavailable).reason;
      expect(reason, contains('bloqué'));
      expect(reason, isNot(contains('relance')));
    });

    test('rend un 429 avec la raison de la limite de dépôts', () async {
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          if (_isToken(request)) return _tokenResponse();
          return http.Response('{}', 429);
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      expect(outcome, isA<KdpSubmissionUnavailable>());
      final String reason = (outcome as KdpSubmissionUnavailable).reason;
      expect(reason, contains('limite'));
      expect(reason, isNot(contains('relance')));
    });

    test('rend une panne d\'Amazon comme une issue inconnue', () async {
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          if (_isToken(request)) return _tokenResponse();
          return http.Response('{}', 503);
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      // Amazon a reçu la demande et n'a pas su la traiter : la soumission
      // existe peut-être déjà.
      expect(outcome, isA<KdpSubmissionUnknown>());
      expect((outcome as KdpSubmissionUnknown).reason, contains('incertaine'));
    });

    test('rend une panne d\'Amazon sur le jeton comme un échec', () async {
      final AmazonKdpGateway gateway = _gateway(
        handler: (http.Request request) async {
          return http.Response('{}', 503);
        },
      );

      final KdpSubmissionOutcome outcome = await gateway.submit(
        _submissionRequest(),
      );

      // Le jeton n'a pas pu être obtenu : le dossier n'est jamais parti.
      expect(outcome, isA<KdpSubmissionUnavailable>());
    });
  });

  group('secrets', () {
    test('ne laisse pas sortir le secret ni le jeton de renouvellement', () {
      final ClassMirror mirror = reflectClass(AmazonKdpGateway);
      final Iterable<String> publicNames = mirror.declarations.keys
          .map(MirrorSystem.getName)
          .where((String name) => !name.startsWith('_'));

      expect(
        publicNames.any((String name) => name.toLowerCase().contains('secret')),
        isFalse,
      );
      expect(
        publicNames.any(
          (String name) => name.toLowerCase().contains('refreshtoken'),
        ),
        isFalse,
      );
    });

    test('ne laisse pas sortir les secrets dans la trace de l\'objet', () {
      final AmazonKdpGateway gateway = AmazonKdpGateway(
        clientId: 'client-id',
        clientSecret: 'le-secret-du-client',
        refreshToken: 'le-jeton-de-renouvellement',
        budget: const Duration(seconds: 30),
      );

      expect(gateway.toString(), isNot(contains('le-secret-du-client')));
      expect(gateway.toString(), isNot(contains('le-jeton-de-renouvellement')));
    });
  });
}
