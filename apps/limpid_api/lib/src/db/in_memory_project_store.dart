import 'package:limpid_core/limpid_core.dart';

import '../http/pagination.dart';
import 'project_record.dart';
import 'project_store.dart';

/// An in-memory [ProjectStore], used by the test suite.
///
/// The store keeps the same invariants as the Postgres implementation:
/// isolation by owner, soft delete and a `(updated_at, id)` sort order.
final class InMemoryProjectStore implements ProjectStore {
  /// Creates an empty store.
  InMemoryProjectStore({UlidGenerator? generator})
    : _ulid = generator ?? UlidGenerator();

  final UlidGenerator _ulid;
  final Map<String, ProjectRecord> _projects = <String, ProjectRecord>{};
  final Map<String, Map<String, ProjectRole>> _members =
      <String, Map<String, ProjectRole>>{};

  /// The projects currently stored, for the assertions of the test suite.
  Map<String, ProjectRecord> get projects =>
      Map<String, ProjectRecord>.unmodifiable(_projects);

  /// Grants [role] to [userId] on [projectId].
  void addMember({
    required String projectId,
    required String userId,
    required ProjectRole role,
  }) {
    final Map<String, ProjectRole> members = _members.putIfAbsent(
      projectId,
      () => <String, ProjectRole>{},
    );
    members[userId] = role;
  }

  @override
  Future<ProjectPage> list({
    required String userId,
    required int limit,
    required String? cursor,
  }) async {
    final List<ProjectRecord> visible = _visibleProjects(userId)
      ..sort(_compareProjects);
    final PageCursorValue? decoded = PageCursor.decode(cursor);
    final List<ProjectRecord> afterCursor = decoded == null
        ? visible
        : visible
              .where((ProjectRecord record) => _isAfter(record, decoded))
              .toList(growable: false);
    final List<ProjectRecord> items = afterCursor
        .take(limit)
        .toList(growable: false);
    final bool hasMore = afterCursor.length > items.length;
    final String? nextCursor = hasMore && items.isNotEmpty
        ? PageCursor.encode(
            items.last.updatedAt.toUtc().toIso8601String(),
            items.last.id,
          )
        : null;
    return ProjectPage(
      items: items,
      total: visible.length,
      nextCursor: nextCursor,
    );
  }

  @override
  Future<List<ProjectRecord>> listAll({required String userId}) async {
    final List<ProjectRecord> owned = _projects.values
        .where((ProjectRecord record) => record.ownerId == userId)
        .toList(growable: false);
    final List<ProjectRecord> shared = _projects.values
        .where(
          (ProjectRecord record) =>
              record.ownerId != userId &&
              (_members[record.id]?.containsKey(userId) ?? false),
        )
        .toList(growable: false);
    final List<ProjectRecord> all = <ProjectRecord>[...owned, ...shared]
      ..sort(_compareByCreation);
    return List<ProjectRecord>.unmodifiable(all);
  }

  @override
  Future<ProjectAccess?> access({
    required String projectId,
    required String userId,
  }) async {
    final ProjectRecord? project = _projects[projectId];
    if (project == null || project.isDeleted) return null;
    if (project.ownerId == userId) {
      return ProjectAccess(project: project, role: ProjectRole.owner);
    }
    final ProjectRole? role = _members[projectId]?[userId];
    if (role == null) return null;
    return ProjectAccess(project: project, role: role);
  }

  @override
  Future<ProjectRecord?> findPublic({required String projectId}) async {
    final ProjectRecord? project = _projects[projectId];
    if (project == null || project.isDeleted) return null;
    if (project.status != ManuscriptStatus.published) return null;
    if (!project.isPublic) return null;
    return project;
  }

  @override
  Future<ProjectRecord> create({
    required String ownerId,
    required String title,
    required String synopsis,
    required ManuscriptStatus status,
    required String language,
    required String orderKey,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    final ProjectRecord record = ProjectRecord(
      id: _ulid.generate().value,
      ownerId: ownerId,
      title: title,
      synopsis: synopsis,
      status: status,
      language: language,
      orderKey: orderKey,
      isPublic: false,
      createdAt: now,
      updatedAt: now,
    );
    _projects[record.id] = record;
    return record;
  }

  @override
  Future<ProjectRecord> update(ProjectRecord record) async {
    final ProjectRecord? existing = _projects[record.id];
    if (existing == null) {
      throw StateError('Unknown project ${record.id}.');
    }
    final ProjectRecord updated = record.copyWith(
      updatedAt: DateTime.now().toUtc(),
    );
    _projects[record.id] = updated;
    return updated;
  }

  @override
  Future<void> softDelete({required String projectId}) async {
    final ProjectRecord? existing = _projects[projectId];
    if (existing == null) return;
    _projects[projectId] = existing.copyWith(
      deletedAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  List<ProjectRecord> _visibleProjects(String userId) {
    return _projects.values
        .where((ProjectRecord record) => !record.isDeleted)
        .where(
          (ProjectRecord record) =>
              record.ownerId == userId ||
              (_members[record.id]?.containsKey(userId) ?? false),
        )
        .toList(growable: false);
  }

  static int _compareProjects(ProjectRecord left, ProjectRecord right) {
    final int byDate = right.updatedAt.compareTo(left.updatedAt);
    if (byDate != 0) return byDate;
    return left.id.compareTo(right.id);
  }

  static int _compareByCreation(ProjectRecord left, ProjectRecord right) {
    final int byDate = left.createdAt.compareTo(right.createdAt);
    if (byDate != 0) return byDate;
    return left.id.compareTo(right.id);
  }

  static bool _isAfter(ProjectRecord record, PageCursorValue cursor) {
    final DateTime updatedAt = DateTime.parse(cursor.updatedAt);
    final int byDate = updatedAt.compareTo(record.updatedAt);
    if (byDate != 0) return byDate > 0;
    return record.id.compareTo(cursor.id) > 0;
  }
}
