import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

void main() {
  group('service des indicateurs', () {
    late _CountingSource source;
    late List<String> logLines;
    late DateTime now;
    late FeatureFlagService service;

    setUp(() {
      source = _CountingSource(<FeatureFlag>[]);
      logLines = <String>[];
      now = DateTime.utc(2026, 10, 26, 12);
      service = FeatureFlagService(
        source: source,
        logger: Logger(level: LogLevel.warning, sink: logLines.add),
        clock: () => now,
      );
    });

    test('un indicateur actif laisse passer la capacité', () async {
      source.flags = <FeatureFlag>[_flag('rag', isEnabled: true)];

      expect(await service.isEnabled('rag'), isTrue);
      expect(await service.isCut(PlanCapability.rag), isFalse);
      await service.ensureCapabilityAvailable(PlanCapability.rag);
      expect(
        await service.announcedCapabilities(SubscriptionPlan.studio),
        contains('rag'),
      );
      expect(service.cutCapabilities, isEmpty);
    });

    test('un indicateur coupé fait tomber la capacité annoncée', () async {
      source.flags = <FeatureFlag>[_flag('rag', isEnabled: false)];

      expect(await service.isEnabled('rag'), isFalse);
      expect(await service.isCut(PlanCapability.rag), isTrue);

      final List<String> announced = await service.announcedCapabilities(
        SubscriptionPlan.studio,
      );
      expect(announced, isNot(contains('rag')));
      expect(announced, contains('api_and_webhooks'));
      expect(service.cutCapabilities, <String>{'rag'});
    });

    test(
      'la capacité coupée est refusée en 403, la fonctionnalité nommée',
      () async {
        source.flags = <FeatureFlag>[_flag('rag', isEnabled: false)];

        await expectLater(
          service.ensureCapabilityAvailable(PlanCapability.rag),
          throwsA(
            isA<ForbiddenException>()
                .having(
                  (ForbiddenException error) => error.statusCode,
                  'statusCode',
                  403,
                )
                .having(
                  (ForbiddenException error) => error.details['feature'],
                  'feature',
                  'rag',
                )
                .having(
                  (ForbiddenException error) => error.message,
                  'message',
                  contains('RAG'),
                ),
          ),
        );
      },
    );

    test('une clef inconnue ne coupe rien et ne casse rien', () async {
      source.flags = <FeatureFlag>[_flag('ai_premium', isEnabled: false)];

      expect(await service.isEnabled('ai_premium'), isTrue);
      expect(await service.isCut(PlanCapability.rag), isFalse);
      await service.ensureCapabilityAvailable(PlanCapability.rag);
      expect(
        await service.announcedCapabilities(SubscriptionPlan.studio),
        contains('rag'),
      );
      expect(service.cutCapabilities, isEmpty);
    });

    test(
      'le changement d\'un indicateur est visible sans redéploiement',
      () async {
        source.flags = <FeatureFlag>[_flag('rag', isEnabled: true)];
        expect(await service.isEnabled('rag'), isTrue);

        // Le back-office coupe l'indicateur et recharge le service.
        source.flags = <FeatureFlag>[_flag('rag', isEnabled: false)];
        await service.reload();

        expect(await service.isEnabled('rag'), isFalse);
        expect(await service.isCut(PlanCapability.rag), isTrue);
      },
    );

    test(
      'un changement fait ailleurs est vu quand le cache a pris du retard',
      () async {
        source.flags = <FeatureFlag>[_flag('rag', isEnabled: true)];
        expect(await service.isEnabled('rag'), isTrue);

        // Une autre instance du serveur, ou une commande en base, change
        // l'indicateur : le service s'en aperçoit sans qu'on le demande.
        source.flags = <FeatureFlag>[_flag('rag', isEnabled: false)];
        now = now.add(const Duration(seconds: 30));

        expect(await service.isEnabled('rag'), isFalse);
      },
    );

    test('le service ne lit pas la base à chaque lecture', () async {
      source.flags = <FeatureFlag>[_flag('rag', isEnabled: true)];

      for (int index = 0; index < 20; index++) {
        expect(await service.isEnabled('rag'), isTrue);
      }

      expect(source.readCount, 1);
    });

    test('un rechargement échoué garde le dernier état connu', () async {
      source.flags = <FeatureFlag>[_flag('rag', isEnabled: true)];
      expect(await service.isEnabled('rag'), isTrue);

      source.failure = const FormatException('la base est injoignable');
      now = now.add(const Duration(seconds: 30));

      expect(await service.isEnabled('rag'), isTrue);
      expect(logLines, hasLength(1));
      expect(logLines.first, contains('feature_flag.reload_failed'));
    });

    test(
      'des rechargements concurrents ne lisent la base qu\'une fois',
      () async {
        source.flags = <FeatureFlag>[_flag('rag', isEnabled: true)];

        await Future.wait<void>(<Future<void>>[
          service.reload(),
          service.reload(),
          service.reload(),
        ]);

        expect(source.readCount, 1);
      },
    );
  });

  group('port de lecture', () {
    test('le port lit les indicateurs écrits par le back-office', () async {
      final InMemoryAdminDatabase admin = InMemoryAdminDatabase();
      final FeatureFlagService service = FeatureFlagService(
        source: AdminFeatureFlagSource(admin),
        logger: Logger(level: LogLevel.warning, sink: (String _) {}),
      );

      await admin.setFeatureFlag(
        key: 'rag',
        isEnabled: false,
        description: 'Incident sur la recherche dans le manuscrit.',
        updatedBy: 'admin-1',
      );

      expect(await service.isEnabled('rag'), isFalse);
      expect(await service.isCut(PlanCapability.rag), isTrue);
    });
  });

  group('chaîne complète', () {
    test('un indicateur coupé par le back-office coupe la capacité', () async {
      final TestServer server = await startTestServer();
      addTearDown(server.stop);

      final InMemoryAdminDatabase admin =
          server.dependencies.admin! as InMemoryAdminDatabase;
      final FeatureFlagService service = FeatureFlagService(
        source: AdminFeatureFlagSource(admin),
        logger: Logger(level: LogLevel.warning, sink: server.logLines.add),
      );

      // Le back-office coupe la recherche dans le manuscrit.
      final http.Response response = await server.put(
        '/v1/admin/feature-flags/rag',
        body: <String, Object?>{'enabled': false},
        headers: <String, String>{
          'authorization': 'Bearer ${_adminToken(server)}',
        },
      );
      expect(response.statusCode, 200);

      // Le service recharge : l'indicateur n'est plus inerte.
      await service.reload();

      expect(await service.isEnabled('rag'), isFalse);
      expect(await service.isCut(PlanCapability.rag), isTrue);
      expect(
        await service.announcedCapabilities(SubscriptionPlan.studio),
        isNot(contains('rag')),
      );
      await expectLater(
        service.ensureCapabilityAvailable(PlanCapability.rag),
        throwsA(isA<ForbiddenException>()),
      );
    });
  });
}

/// Un jeton d'administrateur, signé par la clé du serveur de test.
///
/// Le back-office n'accepte que le rôle porté par le jeton vérifié : le
/// jeton est donc resigned avec la claim `role`.
String _adminToken(TestServer server) {
  final String token = server.issuer.issue(userId: 'admin-1');
  final List<String> parts = token.split('.');
  final Map<String, dynamic> payload =
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
  final String encoded = base64Url.encode(
    utf8.encode(jsonEncode(<String, dynamic>{...payload, 'role': 'admin'})),
  );
  final String signingInput = '${parts[0]}.$encoded';
  final String signature = base64Url.encode(
    server.keyPair.sign(utf8.encode(signingInput)),
  );
  return '$signingInput.$signature';
}

/// Un indicateur de test.
FeatureFlag _flag(String key, {required bool isEnabled}) {
  return FeatureFlag(
    key: key,
    isEnabled: isEnabled,
    description: 'Un indicateur de test.',
    updatedAt: DateTime.utc(2026, 10, 26),
    updatedBy: 'admin-1',
  );
}

/// Une source d'indicateurs qui compte ses lectures.
final class _CountingSource implements FeatureFlagSource {
  /// Crée une source qui renvoie [flags].
  _CountingSource(this.flags);

  /// Les indicateurs que la source renvoie.
  List<FeatureFlag> flags;

  /// Le nombre de lectures faites à la source.
  int readCount = 0;

  /// L'erreur que la source lève, `null` quand elle répond.
  Object? failure;

  @override
  Future<List<FeatureFlag>> listFeatureFlags() async {
    readCount++;
    final Object? error = failure;
    if (error != null) throw error;
    return flags;
  }
}
