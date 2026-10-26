import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_two_factor_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';

void main() {
  group('ApiTwoFactorRepository', () {
    test('lit l’état du compte', () async {
      final ApiTwoFactorRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/me/2fa');
        return _ok(<String, Object?>{
          'enrolled': true,
          'enabled': true,
          'required': false,
        });
      });

      final TwoFactorStatus status = await repository.status();

      expect(status.enrolled, isTrue);
      expect(status.enabled, isTrue);
      expect(status.required, isFalse);
      expect(status.needsActivation, isFalse);
    });

    test('inscrit le compte et rend le secret', () async {
      final ApiTwoFactorRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/me/2fa/enroll');
        return _ok(<String, Object?>{
          'secret': 'JBSWY3DPEHPK3PXP',
          'otpauth_url':
              'otpauth://totp/Limpid:auteur@test?secret=JBSWY3DPEHPK3PXP',
          'digits': 6,
          'period_seconds': 30,
        });
      });

      final TwoFactorEnrollment enrollment = await repository.enroll();

      expect(enrollment.secret, 'JBSWY3DPEHPK3PXP');
      expect(enrollment.otpauthUrl, startsWith('otpauth://totp/Limpid:'));
      expect(enrollment.digits, 6);
      expect(enrollment.periodSeconds, 30);
    });

    test('confirme l’inscription et rend les codes de récupération', () async {
      Map<String, Object?>? body;
      final ApiTwoFactorRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/me/2fa/confirm');
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _ok(<String, Object?>{
          'enabled': true,
          'recovery_codes': <String>['aaaa-bbbb', 'cccc-dddd'],
        });
      });

      final List<String> codes = await repository.confirm(code: '123456');

      expect(body?['code'], '123456');
      expect(codes, <String>['aaaa-bbbb', 'cccc-dddd']);
    });

    test('vérifie un code et rend la preuve', () async {
      Map<String, Object?>? body;
      final ApiTwoFactorRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        expect(request.url.path, '/v1/me/2fa/verify');
        final Object? decoded = jsonDecode(request.body);
        body = decoded is Map<String, Object?> ? decoded : null;
        return _ok(<String, Object?>{
          'verified': true,
          'proof': 'preuve-1',
          'method': 'recovery',
          'expires_at': '2026-12-31T00:00:00.000Z',
        });
      });

      final TwoFactorProof proof = await repository.verify(code: 'aaaa-bbbb');

      expect(body?['code'], 'aaaa-bbbb');
      expect(proof.proof, 'preuve-1');
      expect(proof.method, TwoFactorMethod.recovery);
      expect(proof.expiresAt, DateTime.utc(2026, 12, 31));
      expect(proof.isExpiredAt(DateTime.utc(2026, 12, 30)), isFalse);
      expect(proof.isExpiredAt(DateTime.utc(2027)), isTrue);
    });

    test('désactive le second facteur', () async {
      String? method;
      final ApiTwoFactorRepository repository = _repositoryOf((
        http.Request request,
      ) async {
        method = request.method;
        expect(request.url.path, '/v1/me/2fa');
        return _ok(<String, Object?>{'enabled': false});
      });

      await repository.disable();

      expect(method, 'DELETE');
    });

    test('remonte une erreur typée quand le serveur refuse', () async {
      final ApiTwoFactorRepository repository = _repositoryOf(
        (http.Request request) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'unauthorized',
              'message': 'Le code est invalide.',
            },
          }),
          401,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );

      await expectLater(
        repository.verify(code: '000000'),
        throwsA(isA<ApiUnauthorizedException>()),
      );
    });

    test('refuse une réponse qui n’est pas un objet', () async {
      final ApiTwoFactorRepository repository = _repositoryOf(
        (http.Request request) async => _ok(<Object?>['pas', 'un', 'objet']),
      );

      await expectLater(
        repository.status(),
        throwsA(isA<ApiMalformedResponseException>()),
      );
    });

    test('refuse une confirmation sans codes de récupération', () async {
      final ApiTwoFactorRepository repository = _repositoryOf(
        (http.Request request) async => _ok(<String, Object?>{'enabled': true}),
      );

      await expectLater(
        repository.confirm(code: '123456'),
        throwsA(isA<ApiMalformedResponseException>()),
      );
    });
  });
}

/// Builds a repository talking to a fake server.
ApiTwoFactorRepository _repositoryOf(
  Future<http.Response> Function(http.Request request) handler,
) => ApiTwoFactorRepository(
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
