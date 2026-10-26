import 'package:limpid_core/limpid_core.dart';

import 'project_record.dart';

/// A page of projects.
final class ProjectPage {
  /// Creates a page.
  const ProjectPage({
    required this.items,
    required this.total,
    required this.nextCursor,
  });

  /// The projects of the page.
  final List<ProjectRecord> items;

  /// The total number of projects the caller can see.
  final int total;

  /// The cursor pointing at the next page, `null` when the page is the last
  /// one.
  final String? nextCursor;
}

/// The persistence port of the projects.
///
/// The API never talks to Postgres directly: it goes through this interface,
/// which the test suite replaces with an in-memory implementation.
abstract interface class ProjectStore {
  /// Lists the projects the caller owns or collaborates on.
  Future<ProjectPage> list({
    required String userId,
    required int limit,
    required String? cursor,
  });

  /// Lists every project the caller owns or collaborates on, the soft
  /// deleted ones included.
  ///
  /// The library of the author never shows a deleted project, but the export
  /// of the personal data carries it: the rows live for thirty days (D-19)
  /// and belong to the author until the purge.
  Future<List<ProjectRecord>> listAll({required String userId});

  /// Returns the project and the role of the caller, `null` when the project
  /// does not exist or is out of the caller's scope.
  Future<ProjectAccess?> access({
    required String projectId,
    required String userId,
  });

  /// The published and public project of [projectId].
  ///
  /// The showcase of the published books reads the projects through this
  /// method. The predicate is applied **by the database**: a project is
  /// returned only when it is published (`status = 'published'`), public
  /// (`is_public = TRUE`) and alive (`deleted_at IS NULL`). A private book is
  /// therefore never loaded, and the answer of the showcase never depends on
  /// the size of a manuscript.
  ///
  /// Returns `null` when the project does not exist, when it is not
  /// published and when it is not public: the three cases must never be told
  /// apart.
  Future<ProjectRecord?> findPublic({required String projectId});

  /// Creates a project owned by [ownerId].
  Future<ProjectRecord> create({
    required String ownerId,
    required String title,
    required String synopsis,
    required ManuscriptStatus status,
    required String language,
    required String orderKey,
  });

  /// Stores the new values of [record].
  Future<ProjectRecord> update(ProjectRecord record);

  /// Soft deletes a project; the row survives for thirty days (D-19).
  Future<void> softDelete({required String projectId});
}
