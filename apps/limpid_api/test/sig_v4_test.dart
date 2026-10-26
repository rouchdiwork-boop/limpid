import 'dart:convert';
import 'dart:typed_data';

import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

void main() {
  group('chemin canonique', () {
    test('encode les segments une seule fois', () {
      // Le chemin de `Uri.path` est deja encode : l'encoder encore
      // encoderait deux fois les caracteres reserves, et la signature ne
      // correspondrait plus au document signe.
      final Uri uri = Uri.parse(
        'https://stockage.test/une%20cle/caf%C3%A9.txt',
      );
      expect(SigV4.canonicalUriOf(uri), '/une%20cle/caf%C3%A9.txt');
    });

    test('rend la racine quand le chemin est vide', () {
      expect(SigV4.canonicalUriOf(Uri.parse('https://stockage.test/')), '/');
    });
  });

  group('signature SigV4', () {
    test('reproduit le vecteur de référence d\'AWS', () {
      // Vecteur « Example: GET Object » de la documentation Amazon S3 sur la
      // signature version 4.
      final Map<String, String> headers = SigV4.sign(
        method: 'GET',
        uri: Uri.parse('https://examplebucket.s3.amazonaws.com/test.txt'),
        headers: <String, String>{
          'host': 'examplebucket.s3.amazonaws.com',
          'range': 'bytes=0-9',
          'x-amz-content-sha256': SigV4.hexSha256(Uint8List(0)),
          'x-amz-date': '20130524T000000Z',
        },
        payload: Uint8List(0),
        accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        region: 'us-east-1',
        service: 's3',
        timestamp: DateTime.utc(2013, 5, 24),
      );

      expect(
        headers['authorization'],
        'AWS4-HMAC-SHA256 '
        'Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, '
        'SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, '
        'Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
      );
    });

    test('signe la charge utile avec son empreinte', () {
      final Uint8List payload = utf8.encode('contenu');

      final Map<String, String> headers = SigV4.sign(
        method: 'PUT',
        uri: Uri.parse('https://bucket.r2.cloudflarestorage.com/cle'),
        headers: <String, String>{
          'host': 'bucket.r2.cloudflarestorage.com',
          'x-amz-content-sha256': SigV4.hexSha256(payload),
        },
        payload: payload,
        accessKeyId: 'cle',
        secretAccessKey: 'secret',
        region: 'auto',
        service: 's3',
        timestamp: DateTime.utc(2026, 10, 25, 9, 12, 33),
      );

      expect(headers['x-amz-date'], '20261025T091233Z');
      expect(headers['authorization'], contains('SignedHeaders=host;'));
      expect(
        headers['authorization'],
        contains('20261025/auto/s3/aws4_request'),
      );
    });

    test('change la signature quand la charge utile change', () {
      final Map<String, String> first = SigV4.sign(
        method: 'PUT',
        uri: Uri.parse('https://bucket.r2.cloudflarestorage.com/cle'),
        headers: <String, String>{'host': 'bucket.r2.cloudflarestorage.com'},
        payload: utf8.encode('un'),
        accessKeyId: 'cle',
        secretAccessKey: 'secret',
        region: 'auto',
        service: 's3',
        timestamp: DateTime.utc(2026, 10, 25),
      );
      final Map<String, String> second = SigV4.sign(
        method: 'PUT',
        uri: Uri.parse('https://bucket.r2.cloudflarestorage.com/cle'),
        headers: <String, String>{'host': 'bucket.r2.cloudflarestorage.com'},
        payload: utf8.encode('deux'),
        accessKeyId: 'cle',
        secretAccessKey: 'secret',
        region: 'auto',
        service: 's3',
        timestamp: DateTime.utc(2026, 10, 25),
      );

      expect(first['authorization'], isNot(second['authorization']));
    });

    test('pré-signe une URL de téléchargement', () {
      final Map<String, String> query = SigV4.presignQuery(
        uri: Uri.parse('https://bucket.r2.cloudflarestorage.com/cle'),
        accessKeyId: 'cle',
        secretAccessKey: 'secret',
        region: 'auto',
        service: 's3',
        timestamp: DateTime.utc(2026, 10, 25, 9, 12, 33),
        expires: const Duration(minutes: 15),
      );

      expect(query['X-Amz-Algorithm'], 'AWS4-HMAC-SHA256');
      expect(query['X-Amz-Expires'], '900');
      expect(query['X-Amz-SignedHeaders'], 'host');
      expect(query['X-Amz-Signature'], isA<String>());
      expect(query['X-Amz-Signature'], hasLength(64));
    });
  });
}
