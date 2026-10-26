import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Starts a fake Supabase Auth server that always answers [status] and [body].
Future<HttpServer> startFakeAuthServer({
  required int status,
  required String body,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    await request.drain<void>();
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(body);
    await request.response.close();
  });
  return server;
}

/// A port nobody listens to: the connection is refused right away.
Future<int> closedPort() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close(force: true);
  return port;
}

/// A storage that keeps the PKCE verifier in memory.
final class _MemoryAsyncStorage implements sb.GotrueAsyncStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }
}

/// A client that talks to [port].
sb.SupabaseClient clientAt(int port) {
  final client = sb.SupabaseClient(
    'http://127.0.0.1:$port',
    'test-publishable-key',
    authOptions: sb.AuthClientOptions(pkceAsyncStorage: _MemoryAsyncStorage()),
  );
  addTearDown(client.dispose);
  return client;
}

void main() {
  group('mode Supabase', () {
    test('un échec réseau est signalé comme indisponible', () async {
      final repository = SupabaseAuthRepository(clientAt(await closedPort()));

      await expectLater(
        repository.signInWithPassword(
          'camille@atelier-sable.fr',
          'un-mot-de-passe',
        ),
        throwsA(isA<AuthUnavailableException>()),
      );
    });

    test('une adresse invalide est refusée', () async {
      final repository = SupabaseAuthRepository(clientAt(await closedPort()));

      await expectLater(
        repository.sendMagicLink('pas-une-adresse'),
        throwsA(isA<InvalidEmailException>()),
      );
    });

    test('un mot de passe faux est refusé', () async {
      final server = await startFakeAuthServer(
        status: 400,
        body:
            '{"error":"invalid_grant",'
            '"error_description":"Invalid login credentials"}',
      );
      addTearDown(() => server.close(force: true));
      final repository = SupabaseAuthRepository(clientAt(server.port));

      await expectLater(
        repository.signInWithPassword(
          'camille@atelier-sable.fr',
          'un-mot-de-passe',
        ),
        throwsA(isA<AuthRejectedException>()),
      );
    });

    test('un utilisateur inconnu est refusé', () async {
      final server = await startFakeAuthServer(
        status: 400,
        body:
            '{"error":"user_not_found",'
            '"error_description":"User not found"}',
      );
      addTearDown(() => server.close(force: true));
      final repository = SupabaseAuthRepository(clientAt(server.port));

      await expectLater(
        repository.sendMagicLink('inconnu@atelier-sable.fr'),
        throwsA(isA<AuthRejectedException>()),
      );
    });

    test('trop de tentatives sont signalées', () async {
      final server = await startFakeAuthServer(
        status: 429,
        body:
            '{"error":"over_request_rate_limit",'
            '"error_description":"Too many requests"}',
      );
      addTearDown(() => server.close(force: true));
      final repository = SupabaseAuthRepository(clientAt(server.port));

      await expectLater(
        repository.sendMagicLink('camille@atelier-sable.fr'),
        throwsA(isA<AuthTooManyAttemptsException>()),
      );
    });

    test('une panne du service est signalée comme indisponible', () async {
      final server = await startFakeAuthServer(
        status: 500,
        body: '{"message":"The service is down"}',
      );
      addTearDown(() => server.close(force: true));
      final repository = SupabaseAuthRepository(clientAt(server.port));

      await expectLater(
        repository.sendMagicLink('camille@atelier-sable.fr'),
        throwsA(isA<AuthUnavailableException>()),
      );
    });
  });
}
