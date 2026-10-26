import 'package:limpid_core/limpid_core.dart';

import '../auth/auth_context.dart';
import '../db/project_record.dart';
import '../db/project_store.dart';
import '../errors/app_exception.dart';

/// The access control of the projects.
///
/// The server never trusts the client: the role of the caller is always read
/// from the database, and a project out of the caller's scope is reported as
/// missing so its existence is not disclosed.
abstract final class AccessControl {
  /// Returns the project and the role of [auth] on [projectId].
  ///
  /// Throws a [NotFoundException] when the project does not exist or is out
  /// of the caller's scope.
  static Future<ProjectAccess> requireProject(
    ProjectStore store,
    String projectId,
    AuthContext auth,
  ) async {
    final ProjectAccess? access = await store.access(
      projectId: projectId,
      userId: auth.userId,
    );
    if (access == null) {
      throw const NotFoundException();
    }
    return access;
  }

  /// Returns the project and the role of [auth] on [projectId], and refuses
  /// the callers whose role is not allowed to write.
  static Future<ProjectAccess> requireEditor(
    ProjectStore store,
    String projectId,
    AuthContext auth,
  ) async {
    final ProjectAccess access = await requireProject(store, projectId, auth);
    if (!canEditManuscript(access.role)) {
      throw const ForbiddenException(
        message: 'Votre rôle sur ce projet ne permet pas de le modifier.',
      );
    }
    return access;
  }
}
