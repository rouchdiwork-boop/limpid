import 'package:drift/drift.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The DDL of the memberships of the authors to the projects.
///
/// The table is created by this file, and not by `app_schema.dart`: the
/// memberships are the implementation detail of the scoped reads of the
/// library. The statements are idempotent — the schema is applied on every
/// opening of the database.
const List<String> projectMembershipSchemaStatements = <String>[
  '''
CREATE TABLE IF NOT EXISTS project_members (
  project_id TEXT NOT NULL,
  author_id TEXT NOT NULL,
  PRIMARY KEY (project_id, author_id)
)''',
  'CREATE INDEX IF NOT EXISTS project_members_author '
      'ON project_members (author_id)',
];

/// The store of the memberships of the authors to the projects.
///
/// A project the author only **collaborates** on belongs to somebody else:
/// the ownership alone would hide it from the library of the author. The
/// membership records that the local database knows the project, and it lets
/// the scoped reads keep the project visible for the author who collaborates
/// on it — and for nobody else.
final class ProjectMembershipStore {
  /// Creates a store on top of [database].
  const ProjectMembershipStore(this._database);

  /// The Drift database holding the table.
  final SyncDatabase _database;

  /// Records that [authorId] collaborates on [projectId].
  ///
  /// The write is idempotent: a membership recorded twice is still one
  /// membership.
  Future<void> add({
    required String projectId,
    required String authorId,
  }) async {
    await _database.customStatement(
      'INSERT INTO project_members (project_id, author_id) VALUES (?, ?) '
      'ON CONFLICT(project_id, author_id) DO NOTHING',
      <Object?>[projectId, authorId],
    );
  }

  /// The projects [authorId] collaborates on.
  ///
  /// The list is sorted: the reads that use it must always see the projects
  /// in the same order.
  Future<List<String>> projectsOf(String authorId) async {
    final List<QueryRow> rows = await _database
        .customSelect(
          'SELECT project_id FROM project_members WHERE author_id = ? '
          'ORDER BY project_id ASC',
          variables: <Variable<Object>>[Variable<String>(authorId)],
        )
        .get();
    final List<String> projects = <String>[];
    for (final QueryRow row in rows) {
      final Object? projectId = row.data['project_id'];
      if (projectId is String) projects.add(projectId);
    }
    return List<String>.unmodifiable(projects);
  }
}
