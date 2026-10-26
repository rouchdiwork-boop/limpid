import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart';

/// The directory holding the SQLite migrations.
const String sqliteMigrationsDirectory = 'db/migrations/sqlite';

/// The stores under test.
///
/// A fixture gathers the three persistence ports of the API and the few
/// helpers the contract needs to set them up, so the same scenarios can run
/// against the in-memory stores and against the SQLite ones.
final class StoreFixture {
  /// Creates a fixture.
  const StoreFixture({
    required this.projects,
    required this.sync,
    required this.audit,
    required this.addMember,
    required this.dispose,
  });

  /// The store of the projects.
  final ProjectStore projects;

  /// The store of the sync journal.
  final SyncStore sync;

  /// The audit journal.
  final AuditLog audit;

  /// Grants a role on a project, the way the sharing route does.
  final Future<void> Function({
    required String projectId,
    required String userId,
    required ProjectRole role,
  })
  addMember;

  /// Releases the resources of the fixture.
  final Future<void> Function() dispose;
}

/// Creates a project owned by [ownerId].
Future<ProjectRecord> createProject(
  StoreFixture fixture, {
  String ownerId = 'user-1',
  String title = 'Titre',
}) {
  return fixture.projects.create(
    ownerId: ownerId,
    title: title,
    synopsis: 'Un synopsis.',
    status: ManuscriptStatus.draft,
    language: 'fr-FR',
    orderKey: '5',
  );
}

/// Creates a project and returns its identifier.
Future<String> createProjectId(StoreFixture fixture) async {
  final ProjectRecord project = await createProject(fixture);
  return project.id;
}

/// Builds an operation of the sync journal.
SyncOpRecord buildOperation({
  required String projectId,
  required int lamport,
  String? opId,
}) {
  return SyncOpRecord(
    opId: opId ?? 'op-$lamport',
    projectId: projectId,
    docId: 'doc-1',
    lamport: lamport,
    authorId: 'user-1',
    type: 'insertBlock',
    payload: <String, dynamic>{
      'block_id': 'block-1',
      'content': 'Il pleuvait sur la falaise.',
    },
    schemaVersion: 1,
    createdAt: DateTime.now().toUtc(),
  );
}
