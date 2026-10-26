import 'package:drift/drift.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/limpid_sync.dart';

import 'project_declaration.dart';

/// The prefix of the keys of the aliases of the renamed projects.
///
/// An alias remembers that a project changed its identifier: the server
/// minted another one, and the device adopted it. The alias lets a write
/// that still carries the former identifier land on the project itself
/// instead of creating a second one.
const String projectAliasKeyPrefix = 'sync.project_alias.';

/// The account that holds the aliases of the renamed projects.
///
/// An alias is not the data of an author: it is a fact about the
/// identifiers of the device — the project formerly known as `x` is now
/// known as `y` — and every account that collaborates on the project needs
/// it. The aliases therefore live apart from the preferences of the
/// authors, which belong to an account.
const String deviceAliasAccountId = 'device-aliases';

/// The identity of the projects on the device.
///
/// The store answers the two questions the synchronisation asks about a
/// project: what does the local database know about it, and how does the
/// device adopt the identifier the server minted.
///
/// ## The adoption
///
/// The server mints the identifier of a project: the device sends the
/// identifier it knows, and the server may answer with another one. The
/// device then **adopts** it — the project and everything that points at it
/// change their identifier in a single transaction. The two sides end up
/// with the same identifier, and the showcase of the book points at the
/// project the server knows.
///
/// The adoption is atomic: either every row points at the new identifier,
/// or every row still points at the former one. A device that crashes in
/// the middle never mixes the two.
final class ProjectIdentityStore {
  /// Creates a store on top of [database].
  const ProjectIdentityStore(this._database, {required this.authorId});

  /// The Drift database holding the tables.
  final SyncDatabase _database;

  /// The account the reads are scoped to.
  ///
  /// The local database is shared by every author who uses the device: a
  /// project the author does not own and does not collaborate on is
  /// invisible.
  final String authorId;

  /// The declaration of the local project [projectId].
  ///
  /// The answer is `null` when the device does not know the project, or
  /// when it knows it but it is out of the scope of the author.
  Future<ProjectDeclaration?> read(String projectId) async {
    final List<QueryRow> rows = await _database
        .customSelect(
          'SELECT id, title, synopsis, status, is_public FROM projects '
          'WHERE id = ? AND (owner_id = ? OR id IN ('
          'SELECT project_id FROM project_members WHERE author_id = ?))',
          variables: <Variable<Object>>[
            Variable<String>(projectId),
            Variable<String>(authorId),
            Variable<String>(authorId),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    return _declarationOf(rows.first.data);
  }

  /// Adopts [serverProjectId] as the identifier of the local project
  /// [projectId].
  ///
  /// The former identifier becomes an alias of the new one: a write that
  /// still carries it lands on the project instead of creating a second
  /// one.
  Future<void> adopt({
    required String projectId,
    required String serverProjectId,
  }) async {
    if (projectId == serverProjectId) return;
    await _database.transaction(() async {
      await _execute('UPDATE projects SET id = ? WHERE id = ?', <Object?>[
        serverProjectId,
        projectId,
      ]);
      await _execute(
        'UPDATE chapters SET project_id = ? WHERE project_id = ?',
        <Object?>[serverProjectId, projectId],
      );
      await _execute(
        'UPDATE document_index SET project_id = ? WHERE project_id = ?',
        <Object?>[serverProjectId, projectId],
      );
      await _execute(
        'UPDATE project_members SET project_id = ? WHERE project_id = ?',
        <Object?>[serverProjectId, projectId],
      );
      await _execute(
        'INSERT INTO preferences (account_id, key, value) VALUES (?, ?, ?) '
        'ON CONFLICT(account_id, key) DO UPDATE SET value = excluded.value',
        <Object?>[
          deviceAliasAccountId,
          '$projectAliasKeyPrefix$projectId',
          serverProjectId,
        ],
      );
    });
  }

  /// The identifier the project [projectId] was renamed to.
  ///
  /// The answer is [projectId] itself when the project never changed its
  /// identifier.
  ///
  /// The alias is a fact about the identifiers of the device: it is shared
  /// by every account that collaborates on the project.
  Future<String> canonicalId(String projectId) async {
    final List<QueryRow> rows = await _database
        .customSelect(
          'SELECT value FROM preferences WHERE account_id = ? AND key = ?',
          variables: <Variable<Object>>[
            const Variable<String>(deviceAliasAccountId),
            Variable<String>('$projectAliasKeyPrefix$projectId'),
          ],
        )
        .get();
    if (rows.isEmpty) return projectId;
    final Object? value = rows.first.data['value'];
    return value is String && value.isNotEmpty ? value : projectId;
  }

  /// Reads a declaration from its row.
  static ProjectDeclaration _declarationOf(Map<String, Object?> row) {
    return ProjectDeclaration(
      id: _text(row, 'id'),
      title: _text(row, 'title'),
      synopsis: _text(row, 'synopsis'),
      status: _statusOf(row, 'status'),
      isPublic: _flag(row, 'is_public'),
    );
  }

  /// Runs a statement that writes.
  Future<void> _execute(String sql, List<Object?> args) async {
    await _database.customStatement(sql, args);
  }

  /// Reads a column of text, an empty string when it is missing.
  static String _text(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is String ? value : '';
  }

  /// Reads a column holding a flag, `false` when it is missing.
  static bool _flag(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    if (value is bool) return value;
    if (value is int) return value != 0;
    return false;
  }

  /// Reads a column holding an editorial stage.
  static ManuscriptStatus _statusOf(Map<String, Object?> row, String column) {
    final String name = _text(row, column);
    for (final ManuscriptStatus status in ManuscriptStatus.values) {
      if (status.name == name) return status;
    }
    return ManuscriptStatus.draft;
  }
}
