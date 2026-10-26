import 'dart:convert';
import 'dart:typed_data';

import 'package:limpid_import/limpid_import.dart';
import 'package:limpid_import/testing.dart';
import 'package:test/test.dart';

void main() {
  group('reconnaissance du format', () {
    test('reconnait une extension', () {
      expect(
        ImportFormatDetector.detect(
          ImportRequest(
            fileName: 'livre.docx',
            bytes: Uint8List.fromList(<int>[0]),
          ),
        ),
        ImportFormat.docx,
      );
      expect(
        ImportFormatDetector.detect(
          ImportRequest(
            fileName: 'livre.markdown',
            bytes: Uint8List.fromList(<int>[0]),
          ),
        ),
        ImportFormat.markdown,
      );
    });

    test('reconnait un type MIME', () {
      expect(
        ImportFormatDetector.detect(
          ImportRequest(
            fileName: 'livre',
            contentType: 'application/epub+zip',
            bytes: Uint8List.fromList(<int>[0]),
          ),
        ),
        ImportFormat.epub,
      );
      expect(
        ImportFormatDetector.detect(
          ImportRequest(
            fileName: 'livre',
            contentType: 'text/markdown; charset=utf-8',
            bytes: Uint8List.fromList(<int>[0]),
          ),
        ),
        ImportFormat.markdown,
      );
    });

    test('reconnait un paquet sans nom', () {
      expect(
        ImportFormatDetector.detect(
          ImportRequest(fileName: 'livre', bytes: buildDocx()),
        ),
        ImportFormat.docx,
      );
      expect(
        ImportFormatDetector.detect(
          ImportRequest(fileName: 'livre', bytes: buildOdt()),
        ),
        ImportFormat.odt,
      );
      expect(
        ImportFormatDetector.detect(
          ImportRequest(fileName: 'livre', bytes: buildEpub()),
        ),
        ImportFormat.epub,
      );
    });

    test('reconnait un RTF sans nom', () {
      final Uint8List bytes = Uint8List.fromList(
        utf8.encode('{\\rtf1\\ansi hello}'),
      );
      expect(
        ImportFormatDetector.detect(
          ImportRequest(fileName: 'livre', bytes: bytes),
        ),
        ImportFormat.rtf,
      );
    });

    test('ne reconnait pas un contenu inconnu', () {
      expect(
        ImportFormatDetector.detect(
          ImportRequest(
            fileName: 'livre',
            bytes: Uint8List.fromList(utf8.encode('bonjour')),
          ),
        ),
        isNull,
      );
    });
  });

  group('import d\'un format inconnu', () {
    test('leve une erreur explicite', () async {
      await expectLater(
        const LimpidImporter().import(
          ImportRequest(
            fileName: 'livre.pdf',
            bytes: Uint8List.fromList(utf8.encode('%PDF-1.7')),
          ),
        ),
        throwsA(
          isA<ImportException>().having(
            (ImportException error) => error.code,
            'code',
            ImportErrorCodes.unsupportedFormat,
          ),
        ),
      );
    });
  });
}
