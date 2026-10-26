import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_admin_repository.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/admin_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';

void main() {
  group('ApiAdminRepository', () {
    test('lit la liste des comptes avec leur usage', () async {
      final ApiAdminRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/admin/users');
        return _ok(<Object?>[
          _account(userId: 'auteur-1', plan: 'studio'),
          _account(userId: 'auteur-2', lastActivityAt: null),
        ]);
      });

      final List<AdminAccount> accounts = await repository.accounts();

      expect(accounts, hasLength(2));
      expect(accounts.first.userId, 'auteur-1');
      expect(accounts.first.plan, 'studio');
      expect(accounts.first.projectCount, 3);
      expect(accounts.first.collaborationCount, 2);
      expect(accounts.first.commentCount, 5);
      expect(accounts.first.operationCount, 12);
      expect(accounts.first.lastActivityAt, DateTime.utc(2026, 10, 20, 8));
      expect(accounts.first.isPurged, isFalse);
      expect(accounts.last.plan, isNull);
      expect(accounts.last.lastActivityAt, isNull);
    });

    test('lit le détail d’un compte', () async {
      final ApiAdminRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/admin/users/auteur-1');
        return _ok(_account(userId: 'auteur-1'));
      });

      final AdminAccount account = await repository.account('auteur-1');

      expect(account.userId, 'auteur-1');
      expect(account.projectCount, 3);
    });

    test('lit les indicateurs de fonctionnalité', () async {
      final ApiAdminRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/admin/feature-flags');
        return _ok(<Object?>[
          <String, Object?>{
            'key': 'ai_premium',
            'is_enabled': false,
            'description': "L'assistant premium répond à toutes les demandes.",
            'updated_at': '2026-10-20T08:00:00.000Z',
            'updated_by': 'admin-1',
          },
        ]);
      });

      final List<AdminFeatureFlag> flags = await repository.featureFlags();

      expect(flags, hasLength(1));
      expect(flags.first.key, 'ai_premium');
      expect(flags.first.isEnabled, isFalse);
      expect(flags.first.description, isNotEmpty);
      expect(flags.first.updatedAt, DateTime.utc(2026, 10, 20, 8));
      expect(flags.first.updatedBy, 'admin-1');
    });

    test('active un indicateur', () async {
      Map<String, Object?>? body;
      final ApiAdminRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        // La route d'activation est enregistree en `PUT` : c'est la seule
        // maniere de l'atteindre.
        expect(request.method, 'PUT');
        expect(request.url.path, '/v1/admin/feature-flags/ai_premium');
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _ok(<String, Object?>{
          'key': 'ai_premium',
          'is_enabled': true,
          'description': "L'assistant premium répond à toutes les demandes.",
          'updated_at': '2026-10-26T10:00:00.000Z',
          'updated_by': 'admin-1',
        });
      });

      final AdminFeatureFlag flag = await repository.setFeatureFlag(
        'ai_premium',
        isEnabled: true,
      );

      expect(body?['enabled'], isTrue);
      expect(flag.key, 'ai_premium');
      expect(flag.isEnabled, isTrue);
    });

    test('désactive un indicateur', () async {
      Map<String, Object?>? body;
      final ApiAdminRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _ok(<String, Object?>{
          'key': 'ai_premium',
          'is_enabled': false,
          'description': '',
          'updated_at': '2026-10-26T10:00:00.000Z',
          'updated_by': 'admin-1',
        });
      });

      final AdminFeatureFlag flag = await repository.setFeatureFlag(
        'ai_premium',
        isEnabled: false,
      );

      expect(body?['enabled'], isFalse);
      expect(flag.isEnabled, isFalse);
    });

    test(
      'refuse la lecture d’un compte qui n’est pas administrateur',
      () async {
        final ApiAdminRepository repository = _repositoryOf((
          http.Request request,
        ) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'code': 'forbidden',
                'message': "Cette ressource est réservée à l'administration.",
              },
            }),
            403,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });

        await expectLater(
          repository.accounts(),
          throwsA(
            isA<ApiUnauthorizedException>().having(
              (ApiUnauthorizedException error) => error.statusCode,
              'statusCode',
              403,
            ),
          ),
        );
      },
    );
  });
}

/// Builds a repository talking to a fake server.
ApiAdminRepository _repositoryOf(
  Future<http.Response> Function(http.Request request) handler,
) => ApiAdminRepository(
  client: ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    client: MockClient(handler),
  ),
);

/// Builds a successful answer carrying the envelope of the API.
http.Response _ok(Object? data) => http.Response(
  jsonEncode(<String, Object?>{'data': data}),
  200,
  headers: <String, String>{'content-type': 'application/json'},
);

/// Builds the account the server answers.
Map<String, Object?> _account({
  String userId = 'auteur-1',
  String? plan,
  String? lastActivityAt = '2026-10-20T08:00:00.000Z',
}) {
  return <String, Object?>{
    'user_id': userId,
    'plan': plan,
    'project_count': 3,
    'collaboration_count': 2,
    'comment_count': 5,
    'operation_count': 12,
    'last_activity_at': lastActivityAt,
    'is_purged': false,
  };
}
