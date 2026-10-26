import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

void main() {
  Map<String, String> base() => <String, String>{
    'DATABASE_URL': 'postgres://user:pass@localhost:5432/limpid',
    'SUPABASE_URL': 'https://project.test',
    'SUPABASE_ANON_KEY': 'anon',
    'SUPABASE_SERVICE_ROLE_KEY': 'service-role',
    'REDIS_URL': 'redis://localhost:6379/0',
    'R2_ACCOUNT_ID': 'account',
    'R2_ACCESS_KEY_ID': 'key',
    'R2_SECRET_ACCESS_KEY': 'secret',
    'R2_BUCKET': 'bucket',
    'ANTHROPIC_API_KEY': 'anthropic',
    'STRIPE_SECRET_KEY': 'stripe',
  };

  group('configuration', () {
    test('accepte un environnement complet', () {
      final AppConfig config = AppConfig.fromEnvironment(base());

      expect(config.port, 8080);
      expect(config.expectedIssuer, 'https://project.test/auth/v1');
      expect(config.supabaseJwksUrl, contains('/.well-known/jwks.json'));
      expect(config.r2Endpoint, contains('account'));
      expect(config.logLevel, LogLevel.info);
    });

    test('nomme la variable manquante', () {
      final Map<String, String> environment = base()
        ..['LIMPID_PROFILE'] = 'prod'
        ..['LIMPID_DB_DRIVER'] = 'postgres'
        ..remove('DATABASE_URL');

      expect(
        () => AppConfig.fromEnvironment(environment),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('DATABASE_URL'),
          ),
        ),
      );
    });

    test('nomme chaque variable obligatoire manquante', () {
      for (final String variable in <String>[
        'DATABASE_URL',
        'SUPABASE_URL',
        'SUPABASE_ANON_KEY',
        'SUPABASE_SERVICE_ROLE_KEY',
        'REDIS_URL',
        'R2_ACCOUNT_ID',
        'R2_ACCESS_KEY_ID',
        'R2_SECRET_ACCESS_KEY',
        'R2_BUCKET',
        'ANTHROPIC_API_KEY',
        'STRIPE_SECRET_KEY',
      ]) {
        final Map<String, String> environment = base()
          ..['LIMPID_PROFILE'] = 'prod'
          ..['LIMPID_DB_DRIVER'] = 'postgres'
          ..remove(variable);
        expect(
          () => AppConfig.fromEnvironment(environment),
          throwsA(
            isA<AppException>().having(
              (AppException e) => e.message,
              'message',
              contains(variable),
            ),
          ),
          reason: 'La variable $variable doit être signalée.',
        );
      }
    });

    test('refuse une URL non absolue', () {
      final Map<String, String> environment = base()
        ..['SUPABASE_URL'] = 'pas-une-url';

      expect(
        () => AppConfig.fromEnvironment(environment),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('SUPABASE_URL'),
          ),
        ),
      );
    });

    test('refuse un port invalide', () {
      final Map<String, String> environment = base()
        ..['PORT'] = 'non-un-nombre';

      expect(
        () => AppConfig.fromEnvironment(environment),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('PORT'),
          ),
        ),
      );
    });

    test('lit les origines CORS et le niveau de log', () {
      final Map<String, String> environment = base()
        ..['CORS_ALLOWED_ORIGINS'] = 'https://a.test, https://b.test'
        ..['LOG_LEVEL'] = 'debug';

      final AppConfig config = AppConfig.fromEnvironment(environment);

      expect(config.allowedOrigins, <String>[
        'https://a.test',
        'https://b.test',
      ]);
      expect(config.logLevel, LogLevel.debug);
    });
  });

  group('profil de développement', () {
    test('démarre sans aucune variable quand le moteur est SQLite', () {
      final AppConfig config = AppConfig.fromEnvironment(<String, String>{});

      expect(config.profile, LimpidProfile.dev);
      expect(config.databaseDriver, DatabaseDriver.sqlite);
      expect(config.sqlitePath, '.limpid/limpid.db');
      expect(config.databaseUrl, isNull);
      expect(config.redisUrl, isNull);
      expect(config.hasRedis, isFalse);
      expect(config.hasAiProvider, isFalse);
      expect(config.hasPayments, isFalse);
      expect(config.hasObjectStorage, isFalse);
    });

    test('remplace les services distants par des valeurs explicites', () {
      final AppConfig config = AppConfig.fromEnvironment(<String, String>{});

      expect(config.supabaseUrl, devPlaceholderUrl);
      expect(config.supabaseAnonKey, devPlaceholderSecret);
      expect(config.r2Bucket, devPlaceholderSecret);
      expect(config.anthropicApiKey, devPlaceholderSecret);
      expect(config.stripeSecretKey, devPlaceholderSecret);
    });

    test('accepte un chemin de base SQLite explicite', () {
      final AppConfig config = AppConfig.fromEnvironment(<String, String>{
        'LIMPID_DB_PATH': 'tmp/limpid-dev.db',
      });

      expect(config.sqlitePath, 'tmp/limpid-dev.db');
    });

    test('exige DATABASE_URL quand le moteur est Postgres', () {
      expect(
        () => AppConfig.fromEnvironment(<String, String>{
          'LIMPID_DB_DRIVER': 'postgres',
        }),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('DATABASE_URL'),
          ),
        ),
      );
    });

    test('refuse un moteur inconnu', () {
      expect(
        () => AppConfig.fromEnvironment(<String, String>{
          'LIMPID_DB_DRIVER': 'mysql',
        }),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('LIMPID_DB_DRIVER'),
          ),
        ),
      );
    });

    test('refuse un profil inconnu', () {
      expect(
        () => AppConfig.fromEnvironment(<String, String>{
          'LIMPID_PROFILE': 'staging',
        }),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('LIMPID_PROFILE'),
          ),
        ),
      );
    });
  });

  group('profil de production', () {
    test('exige SUPABASE_URL', () {
      final Map<String, String> environment = base()
        ..['LIMPID_PROFILE'] = 'prod'
        ..remove('SUPABASE_URL');

      expect(
        () => AppConfig.fromEnvironment(environment),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('SUPABASE_URL'),
          ),
        ),
      );
    });

    test('accepte le profil « production »', () {
      final Map<String, String> environment = base()
        ..['LIMPID_PROFILE'] = 'production';

      final AppConfig config = AppConfig.fromEnvironment(environment);

      expect(config.profile, LimpidProfile.prod);
      expect(config.profile.isStrict, isTrue);
    });

    test('refuse de démarrer sur une valeur de substitution', () {
      final Map<String, String> environment = base()
        ..['LIMPID_PROFILE'] = 'prod'
        ..remove('REDIS_URL');

      expect(
        () => AppConfig.fromEnvironment(environment),
        throwsA(
          isA<AppException>().having(
            (AppException e) => e.message,
            'message',
            contains('REDIS_URL'),
          ),
        ),
      );
    });
  });
}
