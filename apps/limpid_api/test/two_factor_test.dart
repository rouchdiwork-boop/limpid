import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'helpers/store_fixture.dart';
import 'helpers/test_keys.dart';
import 'helpers/test_server.dart';

void main() {
  group('RFC 6238', () {
    // Les vecteurs publiés de la RFC 6238 (appendix B) : le secret de
    // 20 octets "12345678901234567890", en HMAC-SHA1, sur huit chiffres.
    const String secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

    test('encode le secret de référence en base32', () {
      expect(encodeBase32(ascii.encode('12345678901234567890')), secret);
    });

    test('reproduit les vecteurs de la RFC 6238', () {
      expect(_codeAt(secret, 59), '94287082');
      expect(_codeAt(secret, 1111111109), '07081804');
      expect(_codeAt(secret, 1111111111), '14050471');
      expect(_codeAt(secret, 1234567890), '89005924');
      expect(_codeAt(secret, 2000000000), '69279037');
      expect(_codeAt(secret, 20000000000), '65353130');
    });

    test('lit et relit un secret encodé en base32', () {
      final String generated = generateTotpSecret();
      expect(decodeBase32(generated), hasLength(totpSecretLength));
      expect(decodeBase32(generated.toLowerCase()), decodeBase32(generated));
    });
  });

  group('double authentification', () {
    late SqliteDatabase database;
    late HttpServer server;
    late TestTokenIssuer issuer;
    late String baseUrl;
    late Map<String, String?> plans;

    setUp(() async {
      database = await SqliteDatabase.openInMemory();
      await SqliteMigrationRunner(
        database: database,
        directory: sqliteMigrationsDirectory,
      ).run();

      plans = <String, String?>{
        'user-free': 'Gratuit',
        'user-pro': 'Pro',
        'user-studio': 'Studio',
      };

      final TestRsaKeyPair keyPair = generateTestKeyPair(bits: 2048);
      issuer = TestTokenIssuer(keyPair);
      final StaticJwksProvider jwks = StaticJwksProvider(<String, JsonWebKey>{
        issuer.kid: JsonWebKey.fromJson(keyPair.toJwk(issuer.kid))!,
      });

      final TwoFactorDatabase twoFactor = SqliteTwoFactorDatabase(database);
      final AppConfig config = testConfig();
      final Router router = Router();
      registerTwoFactorRoutes(
        router,
        twoFactor,
        config,
        planOf: (String userId) async => plans[userId],
      );
      // Une route authentifiée quelconque : elle sert à vérifier que le
      // second facteur est exigé partout.
      router.get('/v1/projects', (Request request) {
        return ApiResponse.ok(<String, Object?>{'items': <Object?>[]});
      });

      final TwoFactorService guard = TwoFactorService(
        database: twoFactor,
        planOf: (String userId) async => plans[userId],
      );
      final Handler handler = const Pipeline()
          .addMiddleware(
            errorHandlerMiddleware(
              logger: Logger(level: LogLevel.warning),
              timeout: config.requestTimeout,
            ),
          )
          .addMiddleware(
            authenticationMiddleware(
              verifier: JwtVerifier(
                jwks: jwks,
                expectedIssuer: 'https://project.test/auth/v1',
              ),
              twoFactorGuard: guard,
            ),
          )
          .addHandler(router.call);

      server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
      await database.close();
    });

    Future<http.Response> read(
      String path, {
      required String userId,
      Map<String, String> headers = const <String, String>{},
    }) {
      return http.get(
        Uri.parse('$baseUrl$path'),
        headers: <String, String>{
          'authorization': 'Bearer ${issuer.issue(userId: userId)}',
          ...headers,
        },
      );
    }

    Future<http.Response> write(
      String path,
      Map<String, Object?> payload, {
      required String userId,
    }) {
      return http.post(
        Uri.parse('$baseUrl$path'),
        headers: <String, String>{
          'authorization': 'Bearer ${issuer.issue(userId: userId)}',
          'content-type': 'application/json',
        },
        body: jsonEncode(payload),
      );
    }

    Future<http.Response> remove(String path, {required String userId}) {
      return http.delete(
        Uri.parse('$baseUrl$path'),
        headers: <String, String>{
          'authorization': 'Bearer ${issuer.issue(userId: userId)}',
        },
      );
    }

    /// Inscrit le compte et renvoie le secret affiché.
    Future<String> enroll(String userId) async {
      final http.Response response = await write(
        '/v1/me/2fa/enroll',
        <String, Object?>{},
        userId: userId,
      );
      expect(response.statusCode, 200);
      final Map<String, dynamic> data = _dataOf(response);
      return data['secret']! as String;
    }

    /// Inscrit le compte et confirme la double authentification.
    Future<List<String>> enrollAndConfirm(String userId) async {
      final String secret = await enroll(userId);
      final http.Response response = await write(
        '/v1/me/2fa/confirm',
        <String, Object?>{'code': totpCode(secret, DateTime.now().toUtc())},
        userId: userId,
      );
      expect(response.statusCode, 200);
      final List<dynamic> codes =
          _dataOf(response)['recovery_codes']! as List<dynamic>;
      return codes.cast<String>();
    }

    /// Le secret enregistré du compte [userId].
    Future<String> secretOf(String userId) async {
      final TwoFactorRecord? record = await SqliteTwoFactorDatabase(
        database,
      ).findByUserId(userId);
      expect(record, isNotNull);
      return record!.secret;
    }

    test('l\'enrôlement ne rend pas le secret actif', () async {
      final http.Response enrolled = await write(
        '/v1/me/2fa/enroll',
        <String, Object?>{},
        userId: 'user-free',
      );

      expect(enrolled.statusCode, 200);
      final Map<String, dynamic> data = _dataOf(enrolled);
      final String secret = data['secret']! as String;
      expect(secret, isNotEmpty);
      expect(data['digits'], 6);
      expect(data['period_seconds'], 30);

      final Uri otpauth = Uri.parse(data['otpauth_url']! as String);
      expect(otpauth.scheme, 'otpauth');
      expect(otpauth.host, 'totp');
      expect(otpauth.path, '/Limpid:user-free@example.test');
      expect(otpauth.queryParameters['secret'], secret);
      expect(otpauth.queryParameters['issuer'], 'Limpid');

      final http.Response state = await read('/v1/me/2fa', userId: 'user-free');
      expect(state.statusCode, 200);
      final Map<String, dynamic> stateData = _dataOf(state);
      expect(stateData['enrolled'], isTrue);
      expect(stateData['enabled'], isFalse);

      // Le compte n'est pas verrouille : il utilise encore l'API.
      final http.Response projects = await read(
        '/v1/projects',
        userId: 'user-free',
      );
      expect(projects.statusCode, 200);
    });

    test('un code correct active la 2FA et rend les codes une fois', () async {
      final String secret = await enroll('user-free');
      final http.Response confirmed = await write(
        '/v1/me/2fa/confirm',
        <String, Object?>{'code': totpCode(secret, DateTime.now().toUtc())},
        userId: 'user-free',
      );

      expect(confirmed.statusCode, 200);
      final Map<String, dynamic> data = _dataOf(confirmed);
      expect(data['enabled'], isTrue);
      final List<dynamic> codes = data['recovery_codes']! as List<dynamic>;
      expect(codes, hasLength(10));

      final http.Response state = await read('/v1/me/2fa', userId: 'user-free');
      expect(_dataOf(state)['enabled'], isTrue);

      // Une seconde confirmation ne rend plus les codes.
      final http.Response again = await write(
        '/v1/me/2fa/confirm',
        <String, Object?>{'code': totpCode(secret, DateTime.now().toUtc())},
        userId: 'user-free',
      );
      expect(again.statusCode, 409);
      expect(_errorOf(again)['code'], 'conflict');
    });

    test('un code de récupération ne sert qu\'une fois', () async {
      final List<String> codes = await enrollAndConfirm('user-free');
      final String recovery = codes.first;

      final http.Response first = await write(
        '/v1/me/2fa/verify',
        <String, Object?>{'code': recovery},
        userId: 'user-free',
      );
      expect(first.statusCode, 200);
      final Map<String, dynamic> data = _dataOf(first);
      expect(data['verified'], isTrue);
      expect(data['method'], 'recovery');
      expect(data['proof'], isA<String>());

      final http.Response second = await write(
        '/v1/me/2fa/verify',
        <String, Object?>{'code': recovery},
        userId: 'user-free',
      );
      expect(second.statusCode, 401);
      expect(_errorOf(second)['code'], 'unauthorized');
    });

    test('la 2FA confirmée est exigée sur les routes authentifiées', () async {
      await enrollAndConfirm('user-free');

      final http.Response withoutProof = await read(
        '/v1/projects',
        userId: 'user-free',
      );
      expect(withoutProof.statusCode, 401);
      final Map<String, dynamic> error = _errorOf(withoutProof);
      expect(error['code'], 'unauthorized');
      expect(
        (error['details']! as Map<String, dynamic>)['feature'],
        'two_factor',
      );

      final http.Response verified = await write(
        '/v1/me/2fa/verify',
        <String, Object?>{
          'code': totpCode(await secretOf('user-free'), DateTime.now().toUtc()),
        },
        userId: 'user-free',
      );
      expect(verified.statusCode, 200);
      final String proof = _dataOf(verified)['proof']! as String;

      final http.Response withProof = await read(
        '/v1/projects',
        userId: 'user-free',
        headers: <String, String>{'x-limpid-2fa': proof},
      );
      expect(withProof.statusCode, 200);
    });

    test('un compte gratuit sans 2FA n\'est pas bloqué', () async {
      final http.Response response = await read(
        '/v1/projects',
        userId: 'user-free',
      );

      expect(response.statusCode, 200);
    });

    test('un compte Pro sans 2FA est refusé et peut s\'inscrire', () async {
      final http.Response response = await read(
        '/v1/projects',
        userId: 'user-pro',
      );

      expect(response.statusCode, 403);
      final Map<String, dynamic> error = _errorOf(response);
      expect(error['code'], 'forbidden');
      expect(
        (error['details']! as Map<String, dynamic>)['feature'],
        'two_factor',
      );

      // Les routes de la double authentification restent accessibles.
      final http.Response enrolled = await write(
        '/v1/me/2fa/enroll',
        <String, Object?>{},
        userId: 'user-pro',
      );
      expect(enrolled.statusCode, 200);
    });

    test('un compte Studio sans 2FA est refusé', () async {
      final http.Response response = await read(
        '/v1/projects',
        userId: 'user-studio',
      );

      expect(response.statusCode, 403);
      expect(_errorOf(response)['code'], 'forbidden');
    });

    test('la suppression désactive la 2FA et invalide les codes', () async {
      final List<String> codes = await enrollAndConfirm('user-free');

      final http.Response deleted = await remove(
        '/v1/me/2fa',
        userId: 'user-free',
      );
      expect(deleted.statusCode, 200);
      expect(_dataOf(deleted)['enabled'], isFalse);

      // Le code de récupération ne sert plus.
      final http.Response verified = await write(
        '/v1/me/2fa/verify',
        <String, Object?>{'code': codes.first},
        userId: 'user-free',
      );
      expect(verified.statusCode, 409);

      // Le compte retrouve l'usage de l'API.
      final http.Response projects = await read(
        '/v1/projects',
        userId: 'user-free',
      );
      expect(projects.statusCode, 200);
    });
  });

  group('fenêtre de tolérance', () {
    late InMemoryTwoFactorDatabase database;
    late DateTime now;
    late TwoFactorService service;

    setUp(() async {
      database = InMemoryTwoFactorDatabase();
      now = DateTime.utc(2026, 10, 25, 12);
      service = TwoFactorService(
        database: database,
        planOf: (String userId) async => 'Gratuit',
        clock: () => now,
      );
    });

    test('refuse un code trop ancien et accepte un pas d\'écart', () async {
      final TwoFactorEnrollment enrollment = await service.enroll(
        userId: 'user-1',
        email: 'user-1@example.test',
      );

      // Un code de trois pas : hors de la fenetre.
      expect(
        () => service.confirm(
          userId: 'user-1',
          code: totpCode(
            enrollment.secret,
            now.subtract(const Duration(seconds: 90)),
          ),
        ),
        throwsA(isA<ValidationException>()),
      );

      // Un code d'un pas : dans la fenetre.
      final List<String> codes = await service.confirm(
        userId: 'user-1',
        code: totpCode(
          enrollment.secret,
          now.subtract(const Duration(seconds: 30)),
        ),
      );
      expect(codes, hasLength(10));
    });

    test('le secret n\'est actif qu\'après la confirmation', () async {
      final TwoFactorEnrollment enrollment = await service.enroll(
        userId: 'user-1',
        email: 'user-1@example.test',
      );

      final TwoFactorRecord? pending = await database.findByUserId('user-1');
      expect(pending, isNotNull);
      expect(pending!.secret, enrollment.secret);
      expect(pending.isEnabled, isFalse);

      await service.confirm(
        userId: 'user-1',
        code: totpCode(enrollment.secret, now),
      );

      final TwoFactorRecord? active = await database.findByUserId('user-1');
      expect(active!.isEnabled, isTrue);
      expect(active.enabledAt, isNotNull);
    });

    test('la preuve du second facteur expire', () async {
      final TwoFactorEnrollment enrollment = await service.enroll(
        userId: 'user-1',
        email: 'user-1@example.test',
      );
      await service.confirm(
        userId: 'user-1',
        code: totpCode(enrollment.secret, now),
      );

      final TwoFactorVerification verification = await service.verify(
        userId: 'user-1',
        code: totpCode(enrollment.secret, now),
      );
      expect(verification.method, 'totp');
      expect(verification.expiresAt.isAfter(now), isTrue);
    });
  });
}

/// Le code TOTP du secret [secret] à l'instant Unix [seconds].
String _codeAt(String secret, int seconds) {
  return totpCode(
    secret,
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
    digits: 8,
  );
}

/// Les donnees d'une reponse reussie.
Map<String, dynamic> _dataOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['data']! as Map<String, dynamic>;
}

/// L'erreur d'une reponse en echec.
Map<String, dynamic> _errorOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['error']! as Map<String, dynamic>;
}
