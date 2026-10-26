import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('démarrage sur SQLite sans aucun secret', () {
    late Directory workspace;
    late String databasePath;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('limpid-dev-');
      databasePath = '${workspace.path}/limpid.db';
    });

    tearDown(() {
      if (workspace.existsSync()) {
        workspace.deleteSync(recursive: true);
      }
    });

    test(
      'démarre, répond sur /health et refuse les requêtes sans jeton',
      () async {
        final AppConfig config = AppConfig.fromEnvironment(<String, String>{
          'PORT': '0',
          'LIMPID_DB_DRIVER': 'sqlite',
          'LIMPID_DB_PATH': databasePath,
        });

        expect(config.profile, LimpidProfile.dev);
        expect(config.databaseDriver, DatabaseDriver.sqlite);
        expect(config.databaseUrl, isNull);

        final AppDependencies dependencies = await buildProductionDependencies(
          config,
        );
        final HttpServer server = await createServer(
          config,
          dependencies: dependencies,
        );
        final String baseUrl = 'http://127.0.0.1:${server.port}';

        final http.Response health = await http.get(
          Uri.parse('$baseUrl/health'),
        );
        expect(health.statusCode, 200);
        final Map<String, dynamic> healthBody =
            jsonDecode(health.body) as Map<String, dynamic>;
        expect((healthBody['data'] as Map<String, dynamic>)['status'], 'ok');

        final http.Response unauthorized = await http.get(
          Uri.parse('$baseUrl/v1/projects'),
        );
        expect(unauthorized.statusCode, 401);
        final Map<String, dynamic> unauthorizedBody =
            jsonDecode(unauthorized.body) as Map<String, dynamic>;
        final Map<String, dynamic> error =
            unauthorizedBody['error'] as Map<String, dynamic>;
        expect(error['code'], 'unauthorized');
        expect(error['message'], isA<String>());
        expect(error['details'], isA<Map<String, dynamic>>());

        await server.close(force: true);
        await dependencies.close();
      },
    );

    test('crée le fichier SQLite et y applique les migrations', () async {
      final AppConfig config = AppConfig.fromEnvironment(<String, String>{
        'PORT': '0',
        'LIMPID_DB_DRIVER': 'sqlite',
        'LIMPID_DB_PATH': databasePath,
      });

      final AppDependencies dependencies = await buildProductionDependencies(
        config,
      );
      await dependencies.close();

      expect(File(databasePath).existsSync(), isTrue);

      final Database connection = sqlite3.open(databasePath);
      final ResultSet tables = connection.select(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final Set<String> names = tables
          .map((Row row) => row['name']! as String)
          .toSet();
      connection.close();

      expect(
        names,
        containsAll(<String>[
          'projects',
          'project_members',
          'sync_ops',
          'audit_log',
          'schema_migrations',
        ]),
      );
    });

    test('ferme proprement la base à l\'arrêt', () async {
      final AppConfig config = AppConfig.fromEnvironment(<String, String>{
        'PORT': '0',
        'LIMPID_DB_DRIVER': 'sqlite',
        'LIMPID_DB_PATH': databasePath,
      });

      final AppDependencies dependencies = await buildProductionDependencies(
        config,
      );
      await dependencies.close();

      expect(
        dependencies.projects.list(userId: 'user-1', limit: 1, cursor: null),
        throwsA(anything),
      );
    });
  });

  group('refus de démarrer', () {
    test('nomme DATABASE_URL quand le moteur est Postgres', () {
      expect(
        () => AppConfig.fromEnvironment(<String, String>{
          'LIMPID_DB_DRIVER': 'postgres',
        }),
        throwsA(
          isA<ConfigException>()
              .having(
                (ConfigException e) => e.variable,
                'variable',
                'DATABASE_URL',
              )
              .having(
                (ConfigException e) => e.message,
                'message',
                contains('DATABASE_URL'),
              ),
        ),
      );
    });

    test('nomme SUPABASE_URL en profil de production', () {
      final Map<String, String> environment = <String, String>{
        'LIMPID_PROFILE': 'prod',
        'DATABASE_URL': 'postgres://user:pass@localhost:5432/limpid',
        'REDIS_URL': 'redis://localhost:6379/0',
        'R2_ACCOUNT_ID': 'account',
        'R2_ACCESS_KEY_ID': 'key',
        'R2_SECRET_ACCESS_KEY': 'secret',
        'R2_BUCKET': 'bucket',
        'ANTHROPIC_API_KEY': 'anthropic',
        'STRIPE_SECRET_KEY': 'stripe',
      };

      expect(
        () => AppConfig.fromEnvironment(environment),
        throwsA(
          isA<ConfigException>()
              .having(
                (ConfigException e) => e.variable,
                'variable',
                'SUPABASE_URL',
              )
              .having(
                (ConfigException e) => e.message,
                'message',
                contains('SUPABASE_URL'),
              ),
        ),
      );
    });

    test('dégrade le cache quand Redis n\'est pas configuré', () async {
      final AppConfig config = AppConfig.fromEnvironment(<String, String>{
        'PORT': '0',
        'LIMPID_DB_DRIVER': 'sqlite',
        'LIMPID_DB_PATH': 'ignored.db',
      });

      expect(config.hasRedis, isFalse);
      expect(config.redisUrl, isNull);

      final DisabledKeyValueStore store = const DisabledKeyValueStore();
      expect(await store.ping(), isFalse);
      expect(
        () => store.get('cle'),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('Redis'),
          ),
        ),
      );
    });
  });
}
