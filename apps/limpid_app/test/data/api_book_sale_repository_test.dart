import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_book_sale_repository.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// L'identifiant du livre des tests.
const String bookId = 'heures';

/// Le titre du livre des tests.
const String bookTitle = 'Les Heures de Cendre';

void main() {
  group('ApiBookSaleRepository', () {
    test('lit le prix sur la route de la vente', () async {
      String? path;
      final ApiBookSaleRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        path = request.url.path;
        return _sale();
      });

      final BookSale? sale = await repository.saleOf(bookId);

      expect(path, '/v1/books/$bookId/sale');
      expect(sale, isNotNull);
      expect(sale!.projectId, bookId);
      expect(sale.title, bookTitle);
      expect(sale.priceInCents, 1290);
      expect(sale.currency, 'eur');
      expect(sale.status, BookSaleStatus.published);
      expect(sale.isPublished, isTrue);
    });

    test('ne montre aucun prix quand le livre n\'est pas en vente', () async {
      final ApiBookSaleRepository repository = _repositoryOf(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'not_found',
              'message': "Ce livre n'est pas en vente.",
            },
          }),
          404,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      final BookSale? sale = await repository.saleOf(bookId);

      expect(sale, isNull);
    });

    test('lit le prix public quand le lecteur n\'a pas de compte', () async {
      final List<String> paths = <String>[];
      final ApiBookSaleRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        paths.add(request.url.path);
        if (request.url.path.startsWith('/v1/public/')) return _sale();
        return http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'unauthorized',
              'message': 'Connectez-vous.',
            },
          }),
          401,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final BookSale? sale = await repository.saleOf(bookId);

      expect(paths, <String>[
        '/v1/books/$bookId/sale',
        '/v1/public/books/$bookId/sale',
      ]);
      expect(sale, isNotNull);
      expect(sale!.priceInCents, 1290);
    });

    test(
      'ne montre aucun prix public quand le livre n\'est pas en vente',
      () async {
        final ApiBookSaleRepository repository = _repositoryOf((
          http.Request request,
        ) async {
          if (request.url.path.startsWith('/v1/public/')) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'error': <String, Object?>{
                  'code': 'not_found',
                  'message': "Ce livre n'est pas en vente.",
                },
              }),
              404,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'code': 'unauthorized',
                'message': 'Connectez-vous.',
              },
            }),
            401,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });

        final BookSale? sale = await repository.saleOf(bookId);

        expect(sale, isNull);
      },
    );

    test('commande le livre avec les deux adresses de retour', () async {
      Map<String, Object?>? body;
      String? path;
      final ApiBookSaleRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        path = request.url.path;
        body = jsonDecode(request.body) as Map<String, Object?>;
        return _order();
      });

      final BookOrder order = await repository.order(
        projectId: bookId,
        successPath: '/retour-paiement/$bookId',
        cancelPath: '/vente/$bookId',
      );

      expect(path, '/v1/checkout/book');
      expect(body!['project_id'], bookId);
      expect(
        body!['success_url'],
        'https://limpid.test/retour-paiement/$bookId',
      );
      expect(body!['cancel_url'], 'https://limpid.test/vente/$bookId');
      expect(order.paymentUrl, 'https://paiement.test/achat/1');
      expect(order.isFree, isFalse);
    });

    test(
      'refuse la commande quand l\'application ne connait pas son adresse',
      () async {
        final ApiBookSaleRepository repository = ApiBookSaleRepository(
          client: ApiClient(
            baseUrl: Uri.parse('https://api.test'),
            client: MockClient((http.Request request) async => _order()),
          ),
        );

        await expectLater(
          repository.order(
            projectId: bookId,
            successPath: '/retour-paiement/$bookId',
            cancelPath: '/vente/$bookId',
          ),
          throwsA(isA<ServiceUnavailableException>()),
        );
      },
    );

    test('lit les livres achetes du compte', () async {
      String? path;
      final ApiBookSaleRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        path = request.url.path;
        return _purchases();
      });

      final List<BookPurchase> purchases = await repository.purchases();

      expect(path, '/v1/purchases');
      expect(purchases, hasLength(1));
      expect(purchases.single.projectId, bookId);
      expect(purchases.single.title, bookTitle);
      expect(purchases.single.amountInCents, 1290);
      expect(purchases.single.grantedAt, DateTime.utc(2026, 3, 12));
    });

    test('telecharge le fichier du livre achete', () async {
      final List<String> paths = <String>[];
      final ApiBookSaleRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        paths.add(request.url.toString());
        if (request.url.host == 'fichiers.test') {
          return http.Response.bytes(<int>[1, 2, 3], 200);
        }
        return _download();
      });

      final BookFile file = await repository.download(bookId);

      expect(paths, <String>[
        'https://api.test/v1/purchases/$bookId/download',
        'https://fichiers.test/heures.epub',
      ]);
      expect(file.fileName, 'heures.epub');
      expect(file.bytes, <int>[1, 2, 3]);
      expect(file.expiresAt, DateTime.utc(2026, 3, 13));
    });

    test('ne garde que le nom du fichier, jamais un chemin', () async {
      final ApiBookSaleRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        if (request.url.host == 'fichiers.test') {
          return http.Response.bytes(<int>[1], 200);
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{
              'project_id': bookId,
              'download_url': 'https://fichiers.test/livre.epub',
              'artifact_key': 'projets/$bookId/../../etc/livre.epub',
              'expires_at': '2026-03-13T00:00:00Z',
            },
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final BookFile file = await repository.download(bookId);

      expect(file.fileName, 'livre.epub');
    });

    test('refuse une reponse qui n\'est pas une vente', () async {
      final ApiBookSaleRepository repository = _repositoryOf(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{'sale': 42},
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      await expectLater(
        repository.saleOf(bookId),
        throwsA(isA<ApiMalformedResponseException>()),
      );
    });
  });
}

/// Construit un depot qui parle a un faux serveur.
ApiBookSaleRepository _repositoryOf(
  Future<http.Response> Function(http.Request request) handler,
) {
  return ApiBookSaleRepository(
    client: ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      client: MockClient(handler),
    ),
    checkoutOrigin: Uri.parse('https://limpid.test'),
  );
}

/// La reponse de la route de la vente.
http.Response _sale() {
  return http.Response(
    jsonEncode(<String, Object?>{
      'data': <String, Object?>{
        'project_id': bookId,
        'owner_id': 'auteur-1',
        'title': bookTitle,
        'price_cents': 1290,
        'currency': 'eur',
        'status': 'published',
        'author_share': 9000,
        'platform_share': 1000,
        'is_free': false,
        'published_at': '2026-03-01T00:00:00Z',
        'updated_at': '2026-03-01T00:00:00Z',
      },
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

/// La reponse de la route de la commande.
http.Response _order() {
  return http.Response(
    jsonEncode(<String, Object?>{
      'data': <String, Object?>{
        'project_id': bookId,
        'price_cents': 1290,
        'amount_cents': 1290,
        'currency': 'eur',
        'discount_cents': 0,
        'promo_code': null,
        'is_free': false,
        'granted': false,
        'session_id': 'session-1',
        'url': 'https://paiement.test/achat/1',
        'status': 'open',
      },
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

/// La reponse de la route des achats.
http.Response _purchases() {
  return http.Response(
    jsonEncode(<String, Object?>{
      'data': <Object?>[
        <String, Object?>{
          'id': 'droit-1',
          'project_id': bookId,
          'source': 'payment_1',
          'granted_at': '2026-03-12T00:00:00Z',
          'amount_cents': 1290,
          'currency': 'eur',
          'author_share': 9000,
          'platform_share': 1000,
          'author_amount_cents': 1161,
          'platform_amount_cents': 129,
          'promo_code': null,
          'title': bookTitle,
          'owner_id': 'auteur-1',
        },
      ],
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

/// La reponse de la route de telechargement.
http.Response _download() {
  return http.Response(
    jsonEncode(<String, Object?>{
      'data': <String, Object?>{
        'project_id': bookId,
        'download_url': 'https://fichiers.test/$bookId.epub',
        'artifact_key': 'projets/$bookId/$bookId.epub',
        'expires_at': '2026-03-13T00:00:00Z',
        'expires_in_seconds': 86400,
      },
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
}
