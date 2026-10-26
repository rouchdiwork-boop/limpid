import 'dart:io';

import 'package:limpid_api/src/db/in_memory_kdp_deposit_store.dart';
import 'package:limpid_api/src/db/kdp_deposit_record.dart';
import 'package:limpid_api/src/db/kdp_record.dart';
import 'package:limpid_api/src/db/sqlite_database.dart';
import 'package:limpid_api/src/db/sqlite_kdp_deposit_store.dart';
import 'package:limpid_api/src/db/sqlite_statement_splitter.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Le dépôt écrit dans la base.
KdpDeposit _deposit({String userId = 'author-1'}) {
  return KdpDeposit(
    id: 'deposit-1',
    publicationId: 'publication-1',
    userId: userId,
    status: KdpDepositStatus.submitted,
    amazonSubmissionId: 'amazon-1',
    issues: const <KdpIssue>[],
    attempts: 1,
    createdAt: DateTime.utc(2026, 10, 25),
    updatedAt: DateTime.utc(2026, 10, 25),
  );
}

void main() {
  group('base en mémoire', () {
    late InMemoryKdpDepositStore store;

    setUp(() {
      store = InMemoryKdpDepositStore();
    });

    test('garde le dépôt et le relit', () async {
      await store.insertDeposit(_deposit());

      final KdpDeposit? found = await store.findDeposit(
        depositId: 'deposit-1',
        userId: 'author-1',
      );

      expect(found, isNotNull);
      expect(found!.status, KdpDepositStatus.submitted);
      expect(found.amazonSubmissionId, 'amazon-1');
    });

    test('refuse une mise à jour qui change de compte', () async {
      await store.insertDeposit(_deposit());

      await expectLater(
        store.updateDeposit(_deposit(userId: 'etranger')),
        throwsStateError,
      );

      final KdpDeposit? found = await store.findDeposit(
        depositId: 'deposit-1',
        userId: 'author-1',
      );
      expect(found?.userId, 'author-1');
    });

    test('refuse la mise à jour d\'un dépôt inconnu', () async {
      await expectLater(store.updateDeposit(_deposit()), throwsStateError);
    });
  });

  group('base SQLite', () {
    late SqliteDatabase database;
    late SqliteKdpDepositStore store;

    setUp(() async {
      database = await SqliteDatabase.openInMemory();
      await _applyMigrations(database);
      store = SqliteKdpDepositStore(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('garde le dépôt et le relit', () async {
      await store.insertDeposit(_deposit());

      final KdpDeposit? found = await store.findDeposit(
        depositId: 'deposit-1',
        userId: 'author-1',
      );

      expect(found, isNotNull);
      expect(found!.status, KdpDepositStatus.submitted);
      expect(found.amazonSubmissionId, 'amazon-1');
      expect(found.attempts, 1);
      expect(found.createdAt.toUtc(), DateTime.utc(2026, 10, 25));
    });

    test('retrouve le dépôt par publication', () async {
      await store.insertDeposit(_deposit());

      final KdpDeposit? found = await store.findDepositByPublication(
        publicationId: 'publication-1',
        userId: 'author-1',
      );

      expect(found?.id, 'deposit-1');
    });

    test('ne montre pas le dépôt à un autre compte', () async {
      await store.insertDeposit(_deposit());

      final KdpDeposit? found = await store.findDeposit(
        depositId: 'deposit-1',
        userId: 'etranger',
      );

      expect(found, isNull);
    });

    test('met à jour le dépôt', () async {
      await store.insertDeposit(_deposit());

      await store.updateDeposit(
        _deposit().copyWith(
          status: KdpDepositStatus.failed,
          failureReason: "Amazon n'a pas répondu à temps.",
          attempts: 2,
        ),
      );

      final KdpDeposit? found = await store.findDeposit(
        depositId: 'deposit-1',
        userId: 'author-1',
      );

      expect(found!.status, KdpDepositStatus.failed);
      expect(found.failureReason, isNotNull);
      expect(found.attempts, 2);
    });

    test('borne la mise à jour par le compte', () async {
      await store.insertDeposit(_deposit());

      // La ligne appartient à « author-1 » : la mise à jour qui prétend
      // la déplacer vers un autre compte ne touche aucune ligne.
      await expectLater(
        store.updateDeposit(_deposit(userId: 'etranger')),
        throwsStateError,
      );

      final KdpDeposit? found = await store.findDeposit(
        depositId: 'deposit-1',
        userId: 'author-1',
      );
      expect(found?.userId, 'author-1');
    });

    test('refuse la mise à jour d\'un dépôt inconnu', () async {
      await expectLater(store.updateDeposit(_deposit()), throwsStateError);
    });

    test('refuse un second dépôt pour la même publication', () async {
      await store.insertDeposit(_deposit());

      // L'index unique de la publication fait foi : la seconde ligne est
      // refusée par la base.
      await expectLater(
        store.insertDeposit(
          _deposit().copyWith(
            status: KdpDepositStatus.pending,
            amazonSubmissionId: null,
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'n\'applique une mise à jour que si l\'état est celui attendu',
      () async {
        await store.insertDeposit(_deposit());

        final bool applied = await store.updateDepositIfStatus(
          _deposit().copyWith(
            status: KdpDepositStatus.submitted,
            amazonSubmissionId: 'amazon-2',
          ),
          expectedStatus: KdpDepositStatus.submitted,
        );

        expect(applied, isTrue);
        final KdpDeposit? found = await store.findDeposit(
          depositId: 'deposit-1',
          userId: 'author-1',
        );
        expect(found?.amazonSubmissionId, 'amazon-2');
      },
    );

    test('refuse une mise à jour quand l\'état a changé', () async {
      await store.insertDeposit(_deposit());

      final bool applied = await store.updateDepositIfStatus(
        _deposit().copyWith(status: KdpDepositStatus.failed),
        expectedStatus: KdpDepositStatus.unknown,
      );

      expect(applied, isFalse);
      final KdpDeposit? found = await store.findDeposit(
        depositId: 'deposit-1',
        userId: 'author-1',
      );
      expect(found?.status, KdpDepositStatus.submitted);
    });

    test('accepte une mise à jour qui ne change rien', () async {
      await store.insertDeposit(_deposit());

      // La ligne existe et appartient au compte : la mise à jour passe,
      // même quand les valeurs sont les mêmes.
      await store.updateDeposit(_deposit());

      final KdpDeposit? found = await store.findDeposit(
        depositId: 'deposit-1',
        userId: 'author-1',
      );
      expect(found, isNotNull);
    });

    test('garde l\'état d\'issue inconnue', () async {
      await store.insertDeposit(
        _deposit().copyWith(
          status: KdpDepositStatus.unknown,
          amazonSubmissionId: null,
          failureReason: "L'issue du dépôt est incertaine.",
        ),
      );

      final KdpDeposit? found = await store.findDeposit(
        depositId: 'deposit-1',
        userId: 'author-1',
      );

      expect(found?.status, KdpDepositStatus.unknown);
      expect(found?.failureReason, contains('incertaine'));
      expect(found?.isResumable, isFalse);
    });
  });
}

/// Applique les migrations utiles au test à [database].
Future<void> _applyMigrations(SqliteDatabase database) async {
  const List<String> files = <String>[
    'db/migrations/sqlite/0015_kdp_deposits.sql',
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
