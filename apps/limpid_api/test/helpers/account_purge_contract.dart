import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

/// The stores under test, for the contract of the purge.
///
/// The fixture gathers the store of the purges and the few helpers the
/// contract needs to set it up, so the same scenarios run against the
/// in-memory store and against the SQLite one.
final class AccountPurgeFixture {
  /// Creates a fixture.
  const AccountPurgeFixture({
    required this.store,
    required this.journal,
    required this.seed,
    required this.remainingRows,
    required this.dispose,
  });

  /// The store of the purges.
  final AccountPurgeStore store;

  /// Records a deletion request in the journal the store reads.
  final Future<void> Function(AuditEntry entry) journal;

  /// Creates the data of an account in the database under test.
  final Future<void> Function(String userId) seed;

  /// The number of rows of the account left in the database.
  final Future<int> Function(String userId) remainingRows;

  /// Releases the resources of the fixture.
  final Future<void> Function() dispose;
}

/// Runs the contract of [AccountPurgeStore].
///
/// The same scenarios run against the in-memory store and against the SQLite
/// one: the equality of the two runs is the proof that the development
/// database behaves like the reference implementation.
void runAccountPurgeContract({
  required String name,
  required Future<AccountPurgeFixture> Function() build,
}) {
  group('contrat de la purge — $name', () {
    late AccountPurgeFixture fixture;

    setUp(() async {
      fixture = await build();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    group('purge', () {
      test('lit les demandes de suppression du journal, la plus ancienne '
          'd\'abord', () async {
        await fixture.journal(
          _deletionRequest('user-1', DateTime.utc(2026, 1, 1)),
        );
        await fixture.journal(
          _deletionRequest('user-2', DateTime.utc(2026, 1, 2)),
        );

        final List<AuditEntry> entries = await fixture.store.journalEntries(
          action: accountDeletionRequestedAction,
          limit: 10,
        );

        expect(entries, hasLength(2));
        expect(entries.first.userId, 'user-1');
        expect(entries.last.userId, 'user-2');
      });

      test('efface les données du compte', () async {
        await fixture.seed('user-1');

        final AccountPurgeOutcome outcome = await fixture.store.purge(
          userId: 'user-1',
          requestedAt: DateTime.utc(2026, 1, 1),
          scheduledFor: DateTime.utc(2026, 1, 31),
          purgedAt: DateTime.utc(2026, 1, 31),
          workerId: 'worker-1',
        );

        expect(outcome.purged, isTrue);
        expect(outcome.projectsDeleted, 1);
        expect(outcome.operationsDeleted, 1);
        expect(outcome.collaborationsDeleted, 1);
        expect(await fixture.remainingRows('user-1'), 0);
      });

      test('refuse de purger deux fois le même compte', () async {
        await fixture.seed('user-1');

        await fixture.store.purge(
          userId: 'user-1',
          requestedAt: DateTime.utc(2026, 1, 1),
          scheduledFor: DateTime.utc(2026, 1, 31),
          purgedAt: DateTime.utc(2026, 1, 31),
          workerId: 'worker-1',
        );
        final AccountPurgeOutcome second = await fixture.store.purge(
          userId: 'user-1',
          requestedAt: DateTime.utc(2026, 1, 1),
          scheduledFor: DateTime.utc(2026, 1, 31),
          purgedAt: DateTime.utc(2026, 2, 2),
          workerId: 'worker-2',
        );

        expect(second.purged, isFalse);
        expect(second.projectsDeleted, 0);
      });

      test('ne touche pas les données d\'un autre compte', () async {
        await fixture.seed('user-1');
        await fixture.seed('user-2');

        await fixture.store.purge(
          userId: 'user-1',
          requestedAt: DateTime.utc(2026, 1, 1),
          scheduledFor: DateTime.utc(2026, 1, 31),
          purgedAt: DateTime.utc(2026, 1, 31),
          workerId: 'worker-1',
        );

        expect(await fixture.remainingRows('user-2'), isPositive);
      });
    });
  });
}

/// Builds the deletion request of an account.
AuditEntry _deletionRequest(String userId, DateTime requestedAt) {
  return AuditEntry(
    userId: userId,
    action: accountDeletionRequestedAction,
    targetType: 'account',
    targetId: userId,
    metadata: <String, Object?>{
      'requested_at': requestedAt.toUtc().toIso8601String(),
      'scheduled_for': requestedAt
          .add(Duration(days: accountDeletionRetentionDays))
          .toUtc()
          .toIso8601String(),
      'retention_days': accountDeletionRetentionDays,
    },
    createdAt: requestedAt,
  );
}
