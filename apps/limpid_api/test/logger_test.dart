import 'dart:convert';

import 'package:limpid_api/src/config/app_config.dart';
import 'package:limpid_api/src/logging/logger.dart';
import 'package:test/test.dart';

/// Le journal ne doit jamais laisser passer un secret, quel que soit le
/// nom que le champ porte.
void main() {
  group('assainissement du journal', () {
    test('retire les champs nommés par leur clé exacte', () {
      final Map<String, Object?> safe = Logger.sanitize(<String, Object?>{
        'password': 'un mot de passe',
        'token': 'un jeton',
        'authorization': 'Bearer abc',
        'email': 'auteur@exemple.fr',
        'action': 'plan.checkout_started',
      });

      expect(safe.containsKey('password'), isFalse);
      expect(safe.containsKey('token'), isFalse);
      expect(safe.containsKey('authorization'), isFalse);
      expect(safe.containsKey('email'), isFalse);
      expect(safe['action'], 'plan.checkout_started');
    });

    test('retire un secret qui porte un nom composé', () {
      // `refresh_token` n'est pas `token` : une liste de correspondance
      // exacte laisserait passer le secret de renouvellement d'Amazon.
      final Map<String, Object?> safe = Logger.sanitize(<String, Object?>{
        'refresh_token': 'un jeton de renouvellement',
        'client_secret': 'un secret de client',
        'access_token': 'un jeton d’accès',
        'api_key': 'une clé',
        'signing_secret': 'un secret de signature',
        'previous_secret_expires_at': '2026-10-26T00:00:00Z',
      });

      expect(safe, isEmpty);
    });

    test('ne retire pas un champ sans secret dans son nom', () {
      final Map<String, Object?> safe = Logger.sanitize(<String, Object?>{
        'stripe_event_type': 'checkout.session.completed',
        'http_status': 200,
        'attempts': 3,
        'target_type': 'subscription',
      });

      expect(safe.length, 4);
      expect(safe['http_status'], 200);
    });

    test('tronque une valeur libre trop longue', () {
      final Map<String, Object?> safe = Logger.sanitize(<String, Object?>{
        'title': 'x' * 900,
      });

      expect((safe['title']! as String).length, lessThan(600));
    });

    test('écrit une ligne JSON par enregistrement', () {
      final List<String> lines = <String>[];
      final Logger logger = Logger(level: LogLevel.info, sink: lines.add);

      logger.info('kdp.deposit', <String, Object?>{
        'client_secret': 'un secret',
        'publication_id': 'pub_1',
      });

      expect(lines, hasLength(1));
      final Map<String, dynamic> record =
          jsonDecode(lines.single) as Map<String, dynamic>;
      expect(record['message'], 'kdp.deposit');
      expect(record['publication_id'], 'pub_1');
      expect(record.containsKey('client_secret'), isFalse);
      expect(lines.single.contains('un secret'), isFalse);
    });
  });
}
