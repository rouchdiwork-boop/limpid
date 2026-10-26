import 'dart:io';

import 'package:limpid_api/src/db/kdp_record.dart';
import 'package:limpid_api/src/db/sqlite_database.dart';
import 'package:limpid_api/src/db/sqlite_kdp_database.dart';
import 'package:limpid_api/src/db/sqlite_statement_splitter.dart';
import 'package:test/test.dart';

/// L'unicite de l'ISBN d'une fiche Amazon KDP.
///
/// Un ISBN designe un ouvrage imprime : deux fiches ne peuvent pas le
/// porter. Le service refuse deja l'ISBN deja pris, mais son controle et
/// son ecriture sont deux moments distincts — deux preparations
/// concurrentes pourraient passer entre les deux. C'est l'index unique de
/// la base qui ferme la fenetre, et c'est lui que ce test prouve.
void main() {
  group('unicite de l ISBN', () {
    late SqliteDatabase database;
    late SqliteKdpDatabase kdp;

    setUp(() async {
      database = await SqliteDatabase.openInMemory();
      await _applyMigrations(database);
      kdp = SqliteKdpDatabase(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('deux fiches ne peuvent pas porter le meme ISBN', () async {
      await kdp.recordPublication(_publication('isbn-1', 'projet-1'));

      // Un autre livre prend le meme ISBN : l'index unique de la base
      // refuse la seconde fiche.
      expect(
        () => kdp.recordPublication(
          _publication('isbn-2', 'projet-2', isbn: '9782264000002'),
        ),
        throwsA(isA<Object>()),
      );
    });

    test('la meme fiche reprend son propre ISBN', () async {
      await kdp.recordPublication(_publication('isbn-1', 'projet-1'));

      // La meme fiche, preparee une seconde fois : elle garde son ISBN.
      final KdpPublication refreshed = await kdp.recordPublication(
        _publication('isbn-1', 'projet-1', title: 'La falaise, tome deux'),
      );

      expect(refreshed.isbn, '9782264000002');
      expect(refreshed.title, 'La falaise, tome deux');
    });

    test('deux fiches sans ISBN coexistent', () async {
      await kdp.recordPublication(
        _publication('isbn-1', 'projet-1', isbn: null),
      );
      await kdp.recordPublication(
        _publication('isbn-2', 'projet-2', isbn: null),
      );

      final KdpPublication? found = await kdp.findPublicationByIsbn(
        isbn: '9782264000002',
      );
      expect(found, isNull);
    });
  });
}

/// La fiche de publication utilisee par le test.
KdpPublication _publication(
  String id,
  String projectId, {
  String title = 'La falaise',
  String? isbn = '9782264000002',
}) {
  return KdpPublication(
    id: id,
    projectId: projectId,
    userId: 'auteur-1',
    title: title,
    author: 'Aurélien Sandre',
    description: 'Un livre sur le sel et la marée.',
    keywords: const <String>[],
    categories: const <String>[],
    issues: const <KdpIssue>[],
    isbn: isbn,
    language: 'fr-FR',
    publisher: null,
    status: KdpPublicationStatus.ready,
    wordCount: 1000,
    pageCount: 10,
    epubKey: 'projet/$projectId/epub.epub',
    pdfKey: 'projet/$projectId/pdf.pdf',
    epubBytes: 10,
    pdfBytes: 10,
    manuscriptVersion: '2026-10-26T00:00:00.000Z',
    createdAt: DateTime.utc(2026, 10, 26),
  );
}

/// Applique les migrations utiles au test a [database].
Future<void> _applyMigrations(SqliteDatabase database) async {
  const List<String> files = <String>[
    'db/migrations/sqlite/0013_kdp_publications.sql',
    'db/migrations/sqlite/2018_kdp_publications_project_unique.sql',
    'db/migrations/sqlite/2023_kdp_publications_isbn_unique.sql',
  ];
  const SqlStatementSplitter splitter = SqlStatementSplitter();
  for (final String file in files) {
    final String script = await File(file).readAsString();
    await database.run(() {
      for (final String statement in splitter.split(script)) {
        database.connection.execute(statement);
      }
    });
  }
}
