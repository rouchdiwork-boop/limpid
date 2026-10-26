import 'package:limpid_api/limpid_api.dart';
import 'package:test/test.dart';

import 'store_fixture.dart';

/// Runs the contract of [AuditLog].
///
/// The journal is append only: the contract checks that a well formed entry
/// is accepted, with and without an explicit timestamp, and that the entries
/// of an author are read back — and only those.
void runAuditLogContract({
  required String name,
  required Future<StoreFixture> Function() build,
}) {
  group('contrat des dépôts — $name', () {
    late StoreFixture fixture;

    setUp(() async {
      fixture = await build();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    group('journal d\'audit', () {
      test('enregistre une entrée', () async {
        await fixture.audit.record(
          AuditEntry(
            userId: 'user-1',
            action: 'project.deleted',
            targetType: 'project',
            targetId: 'projet-1',
            metadata: <String, Object?>{'title': 'Titre'},
            ip: '203.0.113.7',
          ),
        );
      });

      test('enregistre une entrée sans horodatage', () async {
        await fixture.audit.record(
          const AuditEntry(
            userId: 'user-1',
            action: 'export.requested',
            targetType: 'project',
            targetId: 'projet-1',
          ),
        );
      });

      test('relit les entrées de l\'auteur, de la plus récente à la plus '
          'ancienne', () async {
        await fixture.audit.record(
          AuditEntry(
            userId: 'user-1',
            action: 'project.deleted',
            targetType: 'project',
            targetId: 'projet-1',
            metadata: <String, Object?>{'title': 'Titre'},
            ip: '203.0.113.7',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await fixture.audit.record(
          AuditEntry(
            userId: 'user-1',
            action: 'export.requested',
            targetType: 'project',
            targetId: 'projet-2',
            metadata: <String, Object?>{'format': 'epub'},
            ip: '203.0.113.7',
            createdAt: DateTime.utc(2026, 2, 1),
          ),
        );

        final List<AuditEntry> entries = await fixture.audit.entriesOf(
          userId: 'user-1',
          limit: 10,
        );

        expect(entries, hasLength(2));
        expect(entries.first.action, 'export.requested');
        expect(entries.first.metadata['format'], 'epub');
        expect(entries.first.ip, '203.0.113.7');
        expect(entries.last.action, 'project.deleted');
        expect(entries.last.createdAt, DateTime.utc(2026, 1, 1));
      });

      test('ne relit jamais les entrées d\'un autre auteur', () async {
        await fixture.audit.record(
          AuditEntry(
            userId: 'user-2',
            action: 'project.deleted',
            targetType: 'project',
            targetId: 'projet-1',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );

        final List<AuditEntry> entries = await fixture.audit.entriesOf(
          userId: 'user-1',
          limit: 10,
        );

        expect(entries, isEmpty);
      });

      test('relit les entrées d\'une seule action', () async {
        await fixture.audit.record(
          AuditEntry(
            userId: 'user-1',
            action: 'project.deleted',
            targetType: 'project',
            targetId: 'projet-1',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await fixture.audit.record(
          AuditEntry(
            userId: 'user-1',
            action: 'account.deletion_requested',
            targetType: 'account',
            targetId: 'user-1',
            createdAt: DateTime.utc(2026, 3, 1),
          ),
        );

        final List<AuditEntry> entries = await fixture.audit.entriesOf(
          userId: 'user-1',
          limit: 10,
          action: 'account.deletion_requested',
        );

        expect(entries, hasLength(1));
        expect(entries.single.action, 'account.deletion_requested');
        expect(entries.single.targetId, 'user-1');
      });
    });
  });
}
