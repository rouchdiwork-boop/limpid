import 'dart:convert';

import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

void main() {
  group('codec RESP2', () {
    test('encode une commande', () {
      final List<int> encoded = RedisClient.encodeCommand(<String>[
        'SET',
        'clé',
        'valeur',
      ]);

      expect(
        utf8.decode(encoded),
        '*3\r\n\$3\r\nSET\r\n\$4\r\nclé\r\n\$6\r\nvaleur\r\n',
      );
    });

    test('décode une chaîne simple', () {
      final RespReply? reply = decodeReply(utf8.encode('+PONG\r\n'));

      expect(reply, isNotNull);
      expect(reply!.value, 'PONG');
      expect(reply.consumed, 7);
    });

    test('décode un entier', () {
      final RespReply? reply = decodeReply(utf8.encode(':42\r\n'));

      expect(reply!.value, 42);
    });

    test('décode une chaîne brute', () {
      final RespReply? reply = decodeReply(utf8.encode('\$5\r\nhello\r\n'));

      expect(reply!.value, 'hello');
    });

    test('décode une chaîne brute nulle', () {
      final RespReply? reply = decodeReply(utf8.encode('\$-1\r\n'));

      expect(reply!.value, isNull);
    });

    test('décode un tableau', () {
      final RespReply? reply = decodeReply(
        utf8.encode('*2\r\n\$3\r\nfoo\r\n\$3\r\nbar\r\n'),
      );

      expect(reply!.value, <Object?>['foo', 'bar']);
    });

    test('remonte l\'erreur du serveur', () {
      final RespReply? reply = decodeReply(
        utf8.encode('-ERR unknown command\r\n'),
      );

      expect(reply, isNotNull);
      expect(reply!.error, 'ERR unknown command');
    });

    test('renvoie null quand la trame est incomplète', () {
      expect(decodeReply(utf8.encode('\$5\r\nhel')), isNull);
      expect(decodeReply(utf8.encode('*2\r\n\$3\r\nfoo\r\n')), isNull);
    });
  });

  group('magasin clé/valeur', () {
    test('stocke, relit et supprime une valeur', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();

      await store.set('clé', 'valeur');
      expect(await store.get('clé'), 'valeur');

      await store.delete('clé');
      expect(await store.get('clé'), isNull);
    });

    test('expire une valeur', () async {
      final InMemoryKeyValueStore store = InMemoryKeyValueStore();

      await store.set('clé', 'valeur', ttl: const Duration(seconds: 1));
      expect(await store.get('clé'), 'valeur');
    });
  });
}
