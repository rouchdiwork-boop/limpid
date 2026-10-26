import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

void main() {
  late TestServer server;
  late Map<String, String> auth;
  late Map<String, String> otherAuth;

  setUp(() async {
    server = await startTestServer();
    auth = <String, String>{
      'authorization': 'Bearer ${server.tokenFor('user-1')}',
    };
    otherAuth = <String, String>{
      'authorization': 'Bearer ${server.tokenFor('user-2')}',
    };
  });

  tearDown(() async {
    await server.stop();
  });

  group('export des données personnelles', () {
    test('produit une archive ZIP et la dépose dans le stockage', () async {
      final String projectId = await _createProject(server, auth, 'Le livre');
      await _pushScene(server, auth, projectId, 'doc-1', 'Scène une');

      final _Archive archive = await _export(server, auth);

      // La signature d'un ZIP : le fichier commence par « PK ».
      expect(archive.bytes.sublist(0, 2), <int>[0x50, 0x4b]);
      expect(archive.names, isNotEmpty);
      expect(archive.names.first, 'manifest.json');

      // L'archive est déposée dans le stockage objet : la réponse ne porte
      // qu'une URL signée, jamais le fichier.
      expect(
        archive.data['storage_key'],
        startsWith('account-exports/user-1/'),
      );
      expect(archive.data['download_url'], contains('account-exports/user-1/'));
      expect(archive.data['mime_type'], 'application/zip');
      expect(archive.data['size_bytes'], archive.bytes.length);
      expect(server.storage.keys, contains(archive.data['storage_key']));
    });

    test(
      'porte les manuscrits, les assets, les réglages et l\'historique',
      () async {
        final String projectId = await _createProject(server, auth, 'Le livre');
        await _pushScene(server, auth, projectId, 'doc-1', 'Scène une');
        await server.storage.put(
          key: 'exports/$projectId/le-livre.epub',
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
          contentType: 'application/epub+zip',
        );
        await _seedSecrets(server);

        final _Archive archive = await _export(server, auth);

        // Les manuscrits.
        expect(
          archive.names,
          contains('projects/$projectId/documents/doc-1.json'),
        );
        expect(
          archive.names,
          contains('projects/$projectId/manuscript/doc-1.md'),
        );
        expect(
          archive.text('projects/$projectId/manuscript/doc-1.md'),
          contains('Scène une'),
        );

        // Les assets.
        expect(archive.names, contains('assets/$projectId/le-livre.epub'));
        expect(archive.file('assets/$projectId/le-livre.epub'), <int>[
          1,
          2,
          3,
          4,
        ]);

        // Les réglages.
        expect(archive.names, contains('account/settings.json'));
        final Map<String, dynamic> settings = _jsonOf(
          archive.text('account/settings.json'),
        );
        expect(settings['api_keys'], hasLength(1));
        expect(settings['webhook_endpoints'], hasLength(1));

        // La double authentification est décrite, jamais son secret.
        final Map<String, dynamic> twoFactor =
            settings['two_factor'] as Map<String, dynamic>;
        expect(twoFactor['is_enabled'], isFalse);
        expect(twoFactor.containsKey('secret'), isFalse);

        // L'historique de compte.
        expect(archive.names, contains('account/audit-log.json'));
        expect(archive.names, contains('account/plan.json'));
        expect(archive.names, contains('account/usage.json'));
      },
    );

    test('le manifeste décrit le contenu de l\'archive', () async {
      final String projectId = await _createProject(server, auth, 'Le livre');
      await _pushScene(server, auth, projectId, 'doc-1', 'Scène une');

      final _Archive archive = await _export(server, auth);
      final Map<String, dynamic> manifest = _jsonOf(
        archive.text('manifest.json'),
      );

      expect(manifest['format'], 'limpid-account-export');
      expect(manifest['format_version'], 2);
      expect(manifest['exported_at'], isA<String>());

      final List<dynamic> contents = manifest['contents'] as List<dynamic>;
      final List<String> described = contents
          .map((dynamic entry) => (entry as Map<String, dynamic>)['path'])
          .cast<String>()
          .toList(growable: false);
      expect(described, contains('account/account.json'));
      expect(described, contains('projects/$projectId/documents/doc-1.json'));
      for (final dynamic entry in contents) {
        final Map<String, dynamic> described_ = entry as Map<String, dynamic>;
        expect(described_['format'], isA<String>());
      }
    });

    test('ne porte aucun secret', () async {
      final String projectId = await _createProject(server, auth, 'Le livre');
      await _pushScene(server, auth, projectId, 'doc-1', 'Scène une');
      await _seedSecrets(server);

      final _Archive archive = await _export(server, auth);

      for (final String name in archive.names) {
        final String content = utf8.decode(
          archive.file(name),
          allowMalformed: true,
        );
        expect(content, isNot(contains(totpSecret)));
        expect(content, isNot(contains(webhookSecret)));
        expect(content, isNot(contains(apiKeyHash)));
      }

      // Les réglages du compte sont bien là : ce sont les secrets qui
      // manque, pas les réglages.
      final Map<String, dynamic> settings = _jsonOf(
        archive.text('account/settings.json'),
      );
      expect(
        ((settings['api_keys'] as List<dynamic>).single
            as Map<String, dynamic>)['name'],
        'Intégration',
      );
      expect(
        ((settings['webhook_endpoints'] as List<dynamic>).single
            as Map<String, dynamic>)['url'],
        'https://example.test/hook',
      );
    });

    test('ne porte rien d\'un autre compte', () async {
      final String mine = await _createProject(server, auth, 'Le mien');
      await _pushScene(server, auth, mine, 'doc-mine', 'Ma scène');

      final String theirs = await _createProject(server, otherAuth, 'Le sien');
      await _pushScene(
        server,
        otherAuth,
        theirs,
        'doc-theirs',
        'Sa scène',
        'user-2',
      );
      await server.delete('/v1/projects/$theirs', headers: otherAuth);

      final _Archive archive = await _export(server, auth);

      // L'archive porte le livre de l'auteur...
      expect(archive.names, contains('projects/$mine/documents/doc-mine.json'));
      expect(
        archive.text('projects/$mine/manuscript/doc-mine.md'),
        contains('Ma scène'),
      );

      // ... et rien de celui de l'autre compte.
      for (final String name in archive.names) {
        final String content = utf8.decode(
          archive.file(name),
          allowMalformed: true,
        );
        expect(content, isNot(contains(theirs)), reason: name);
        expect(content, isNot(contains('doc-theirs')), reason: name);
        expect(content, isNot(contains('Sa scène')), reason: name);
        expect(content, isNot(contains('user-2')), reason: name);
      }
    });

    test('est déterministe', () async {
      final String projectId = await _createProject(server, auth, 'Le livre');
      await _pushScene(server, auth, projectId, 'doc-1', 'Scène une');

      final _Archive first = await _export(server, auth);
      final _Archive second = await _export(server, auth);

      // Les mêmes entrées, dans le même ordre.
      expect(second.names, first.names);

      for (final String name in first.names) {
        if (name == 'manifest.json') {
          // Le manifeste décrit le contenu de l'archive : il porte la date
          // de l'export et la taille du journal, qui a grandi d'une
          // entrée. Ce qui le décrit — les chemins et les formats — ne
          // change pas.
          expect(
            _describedOf(second.text(name)),
            _describedOf(first.text(name)),
          );
          continue;
        }
        if (name == 'account/account.json') {
          // Cette entrée porte la date de l'export : c'est la seule
          // différence entre deux exports d'un même compte.
          expect(
            _withoutDate(second.text(name)),
            _withoutDate(first.text(name)),
          );
          continue;
        }
        if (name == 'account/audit-log.json') {
          // Le journal porte la demande d'export du premier export : c'est
          // la seule différence, et elle est la preuve que la demande est
          // journalisée.
          expect(_journalOf(second.text(name)), _journalOf(first.text(name)));
          continue;
        }
        expect(second.file(name), first.file(name), reason: name);
      }
    });

    test(
      'porte l\'historique entier, sans le plafond de mille entrées',
      () async {
        for (var index = 0; index < 1200; index++) {
          server.audit.entries.add(
            AuditEntry(
              userId: 'user-1',
              action: 'export.requested',
              targetType: 'project',
              targetId: 'projet-$index',
              createdAt: DateTime.now().toUtc(),
            ),
          );
        }

        final _Archive archive = await _export(server, auth);
        final Map<String, dynamic> journal = _jsonOf(
          archive.text('account/audit-log.json'),
        );

        expect(journal['count'], greaterThanOrEqualTo(1200));
        expect(journal['truncated'], isFalse);
      },
    );

    test('dit quand un artefact n\'a pas pu être embarqué', () async {
      final String projectId = await _createProject(server, auth, 'Le livre');
      for (var index = 0; index < 201; index++) {
        await server.storage.put(
          key: 'exports/$projectId/couverture-$index.bin',
          bytes: Uint8List.fromList(<int>[index]),
          contentType: 'application/octet-stream',
        );
      }

      final _Archive archive = await _export(server, auth);
      final Map<String, dynamic> manifest = _jsonOf(
        archive.text('manifest.json'),
      );
      final Map<String, dynamic> counts =
          manifest['counts'] as Map<String, dynamic>;

      // L'archive embarque deux cents artefacts, et elle dit qu'elle en a
      // laissé un de côté : un export partiel se dit, il ne se cache pas.
      expect(counts['assets'], 200);
      expect(counts['assets_omitted'], 1);
      expect(
        (manifest['notes'] as List<dynamic>).join(' '),
        contains('1 artefact(s)'),
      );
    });

    test('journalise la demande dans l\'audit', () async {
      await server.get('/v1/me/export', headers: auth);

      expect(
        server.audit.entries.any(
          (AuditEntry entry) =>
              entry.action == 'account.export_requested' &&
              entry.userId == 'user-1',
        ),
        isTrue,
      );
    });

    test(
      'porte aussi les projets supprimés, qui vivent encore trente jours',
      () async {
        final String projectId = await _createProject(server, auth, 'Le livre');
        await server.delete('/v1/projects/$projectId', headers: auth);

        final _Archive archive = await _export(server, auth);
        final Map<String, dynamic> project = _jsonOf(
          archive.text('projects/$projectId/project.json'),
        );

        expect((project['project'] as Map<String, dynamic>)['id'], projectId);
        expect(
          (project['project'] as Map<String, dynamic>)['deleted_at'],
          isA<String>(),
        );
      },
    );

    test('exige une authentification', () async {
      final http.Response response = await server.get('/v1/me/export');

      expect(response.statusCode, 401);
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      expect((body['error'] as Map<String, dynamic>)['code'], 'unauthorized');
    });
  });

  group('suppression du compte', () {
    test('exige la confirmation explicite', () async {
      final http.Response withoutBody = await server.delete(
        '/v1/me',
        headers: auth,
      );
      expect(withoutBody.statusCode, 400);

      final http.Response refused = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': false},
      );
      expect(refused.statusCode, 400);
      final Map<String, dynamic> body =
          jsonDecode(refused.body) as Map<String, dynamic>;
      expect(
        (body['error'] as Map<String, dynamic>)['code'],
        'validation_failed',
      );
      expect(
        server.audit.entries.where(
          (AuditEntry entry) => entry.action == 'account.deletion_requested',
        ),
        isEmpty,
      );
    });

    test('journalise la demande et fixe l\'échéance à trente jours', () async {
      final http.Response response = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': true},
      );

      expect(response.statusCode, 200);
      final Map<String, dynamic> data = _dataOf(response);
      expect(data['status'], 'pending_deletion');
      expect(data['retention_days'], 30);

      final DateTime requestedAt = DateTime.parse(
        data['requested_at'] as String,
      );
      final DateTime scheduledFor = DateTime.parse(
        data['scheduled_for'] as String,
      );
      expect(scheduledFor.difference(requestedAt).inDays, 30);

      final List<AuditEntry> deletions = server.audit.entries
          .where(
            (AuditEntry entry) => entry.action == 'account.deletion_requested',
          )
          .toList(growable: false);
      expect(deletions, hasLength(1));
      final AuditEntry entry = deletions.single;
      expect(entry.userId, 'user-1');
      expect(entry.targetType, 'account');
      expect(entry.metadata['retention_days'], 30);
    });

    test('est idempotente', () async {
      final http.Response first = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': true},
      );
      final http.Response second = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': true},
      );

      expect(first.statusCode, 200);
      expect(second.statusCode, 200);
      expect(_dataOf(second), _dataOf(first));

      expect(
        server.audit.entries.where(
          (AuditEntry entry) => entry.action == 'account.deletion_requested',
        ),
        hasLength(1),
      );
    });

    test('exige une authentification', () async {
      final http.Response response = await server.delete(
        '/v1/me',
        body: <String, Object?>{'confirm': true},
      );

      expect(response.statusCode, 401);
    });

    test('reste idempotente quand le journal grandit', () async {
      final http.Response first = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': true},
      );

      for (var index = 0; index < 60; index++) {
        server.audit.entries.add(
          AuditEntry(
            userId: 'user-1',
            action: 'export.requested',
            targetType: 'project',
            targetId: 'projet-$index',
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }

      final http.Response second = await server.delete(
        '/v1/me',
        headers: auth,
        body: <String, Object?>{'confirm': true},
      );

      expect(_dataOf(second), _dataOf(first));
      expect(
        server.audit.entries.where(
          (AuditEntry entry) => entry.action == 'account.deletion_requested',
        ),
        hasLength(1),
      );
    });
  });
}

/// Le secret de la double authentification, semé par le test.
const String totpSecret = 'JBSWY3DPEHPK3PXP';

/// Le secret du point de rappel, semé par le test.
const String webhookSecret = 'secret-de-signature-du-point-de-rappel';

/// L'empreinte de la clé d'API, semée par le test.
const String apiKeyHash = '0123456789abcdef0123456789abcdef';

/// L'archive relue dans le stockage après un export.
final class _Archive {
  _Archive({required this.bytes, required this.data});

  final Uint8List bytes;
  final Map<String, dynamic> data;

  late final _ZipReader _zip = _ZipReader(bytes);

  List<String> get names => _zip.names;

  Uint8List file(String name) => _zip.file(name);

  String text(String name) => _zip.text(name);
}

/// Le lecteur d'un conteneur ZIP, écrit pour la suite de tests.
///
/// La suite analyse le répertoire central et décompresse les entrées : elle
/// lit l'archive comme le fait un archiveur.
final class _ZipReader {
  _ZipReader(this.bytes);

  final Uint8List bytes;

  late final _ZipDirectory _directory = _ZipDirectory(bytes);

  List<String> get names => _directory.names;

  Uint8List file(String name) {
    final _ZipEntry entry = _directory.entryOf(name);
    final Uint8List compressed = Uint8List.sublistView(
      bytes,
      entry.dataOffset,
      entry.dataOffset + entry.compressedSize,
    );
    return Uint8List.fromList(ZLibCodec(raw: true).decode(compressed));
  }

  String text(String name) => utf8.decode(file(name));
}

/// Le répertoire central d'un conteneur ZIP.
final class _ZipDirectory {
  _ZipDirectory(this.bytes) {
    final ByteData data = ByteData.sublistView(bytes);
    final int end = _endOfCentralDirectory();
    final int count = data.getUint16(end + 10, Endian.little);
    int offset = data.getUint32(end + 16, Endian.little);
    for (var index = 0; index < count; index++) {
      final int nameLength = data.getUint16(offset + 28, Endian.little);
      final int extraLength = data.getUint16(offset + 30, Endian.little);
      final int commentLength = data.getUint16(offset + 32, Endian.little);
      final int localOffset = data.getUint32(offset + 42, Endian.little);
      final int localNameLength = data.getUint16(
        localOffset + 26,
        Endian.little,
      );
      final int localExtraLength = data.getUint16(
        localOffset + 28,
        Endian.little,
      );
      _entries.add(
        _ZipEntry(
          name: utf8.decode(
            bytes.sublist(offset + 46, offset + 46 + nameLength),
          ),
          dataOffset: localOffset + 30 + localNameLength + localExtraLength,
          compressedSize: data.getUint32(offset + 20, Endian.little),
        ),
      );
      offset += 46 + nameLength + extraLength + commentLength;
    }
  }

  final Uint8List bytes;
  final List<_ZipEntry> _entries = <_ZipEntry>[];

  List<String> get names =>
      _entries.map((_ZipEntry entry) => entry.name).toList(growable: false);

  _ZipEntry entryOf(String name) {
    for (final _ZipEntry entry in _entries) {
      if (entry.name == name) return entry;
    }
    throw StateError('L\'archive ne porte aucune entrée nommée "$name".');
  }

  int _endOfCentralDirectory() {
    for (var index = bytes.length - 22; index >= 0; index--) {
      if (bytes[index] == 0x50 &&
          bytes[index + 1] == 0x4b &&
          bytes[index + 2] == 0x05 &&
          bytes[index + 3] == 0x06) {
        return index;
      }
    }
    throw StateError('L\'archive ne porte aucun répertoire central.');
  }
}

/// Une entrée du répertoire central.
final class _ZipEntry {
  const _ZipEntry({
    required this.name,
    required this.dataOffset,
    required this.compressedSize,
  });

  final String name;
  final int dataOffset;
  final int compressedSize;
}

/// Exporte le compte et relit l'archive qu'il a produite.
Future<_Archive> _export(TestServer server, Map<String, String> headers) async {
  final http.Response response = await server.get(
    '/v1/me/export',
    headers: headers,
  );
  expect(response.statusCode, 200);

  final Map<String, dynamic> data = _dataOf(response);
  final String key = data['storage_key'] as String;
  final ObjectStorageReader storage =
      server.dependencies.storage as ObjectStorageReader;
  final Uint8List? bytes = await storage.readObject(key: key);
  expect(bytes, isNotNull);

  return _Archive(bytes: bytes!, data: data);
}

/// Seme les secrets du compte : ils ne doivent jamais voyager dans
/// l'archive.
Future<void> _seedSecrets(TestServer server) async {
  final InMemoryTwoFactorDatabase twoFactor =
      server.dependencies.twoFactor! as InMemoryTwoFactorDatabase;
  await twoFactor.savePendingSecret(
    userId: 'user-1',
    secret: totpSecret,
    createdAt: DateTime.now().toUtc(),
  );

  final InMemoryWebhookDatabase webhooks =
      server.dependencies.webhooks! as InMemoryWebhookDatabase;
  await webhooks.insertEndpoint(
    WebhookEndpointRecord(
      id: 'point-1',
      userId: 'user-1',
      url: 'https://example.test/hook',
      events: <String>{'project.published'},
      secret: webhookSecret,
      isActive: true,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    ),
  );
  await webhooks.insertApiKey(
    ApiKeyRecord(
      id: 'cle-1',
      userId: 'user-1',
      name: 'Intégration',
      keyHash: apiKeyHash,
      scopes: <String>{'read'},
      isActive: true,
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

/// La charge utile d'un document JSON, sans sa date d'export.
Map<String, dynamic> _withoutDate(String text) {
  final Map<String, dynamic> payload = _jsonOf(text)..remove('exported_at');
  return payload;
}

/// Les entrées décrites par le manifeste, sans leur taille.
///
/// La taille du journal change d'un export à l'autre : le journal porte la
/// demande d'export du premier export. Ce que le manifeste décrit — les
/// chemins et les formats — ne change pas.
List<String> _describedOf(String text) {
  final Map<String, dynamic> manifest = _jsonOf(text);
  return (manifest['contents'] as List<dynamic>)
      .map((dynamic entry) {
        final Map<String, dynamic> described = entry as Map<String, dynamic>;
        return '${described['path']} (${described['format']})';
      })
      .toList(growable: false);
}

/// The entries of the journal, sans la demande d'export elle-même.
List<dynamic> _journalOf(String text) {
  final Map<String, dynamic> payload = _jsonOf(text);
  return (payload['entries'] as List<dynamic>)
      .where(
        (dynamic entry) =>
            (entry as Map<String, dynamic>)['action'] !=
            'account.export_requested',
      )
      .toList(growable: false);
}

Map<String, dynamic> _jsonOf(String text) =>
    jsonDecode(text) as Map<String, dynamic>;

Map<String, dynamic> _dataOf(http.Response response) {
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return body['data'] as Map<String, dynamic>;
}

Future<String> _createProject(
  TestServer server,
  Map<String, String> headers,
  String title,
) async {
  final http.Response response = await server.post(
    '/v1/projects',
    headers: headers,
    body: <String, Object?>{'title': title},
  );
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return (body['data'] as Map<String, dynamic>)['id'] as String;
}

Future<void> _pushScene(
  TestServer server,
  Map<String, String> headers,
  String projectId,
  String docId,
  String content, [
  String authorId = 'user-1',
]) async {
  await server.post(
    '/v1/projects/$projectId/ops',
    headers: headers,
    body: <String, Object?>{
      'operations': <dynamic>[
        <String, Object?>{
          'op_id': '$docId-op-1',
          'doc_id': docId,
          'lamport': 1,
          'author_id': authorId,
          'type': 'insertBlock',
          'payload': <String, Object?>{
            'block_id': '$docId-block-1',
            'parent_id': null,
            'order_key': '5',
            'type': 'paragraph',
            'content': content,
          },
          'schema_version': 1,
        },
      ],
    },
  );
}
