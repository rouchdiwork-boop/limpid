import 'package:limpid_core/limpid_core.dart';

/// A project as stored by the API.
///
/// The record mirrors the `projects` table described in
/// ARCHITECTURE.md §4.1, restricted to the columns the API actually uses.
final class ProjectRecord {
  /// Creates a project record.
  const ProjectRecord({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.synopsis,
    required this.status,
    required this.language,
    required this.orderKey,
    required this.isPublic,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  /// The identifier of the project.
  final String id;

  /// The account owning the project.
  final String ownerId;

  /// The title of the project.
  final String title;

  /// The synopsis of the project.
  final String synopsis;

  /// The editorial stage of the project.
  final ManuscriptStatus status;

  /// The language of the manuscript, as a BCP 47 tag.
  final String language;

  /// The fractional index of the project in the library.
  final String orderKey;

  /// Whether the project is visible on the public showcase.
  final bool isPublic;

  /// The creation timestamp.
  final DateTime createdAt;

  /// The last modification timestamp.
  final DateTime updatedAt;

  /// The soft deletion timestamp, `null` when the project is alive.
  final DateTime? deletedAt;

  /// Whether the project was soft deleted.
  bool get isDeleted => deletedAt != null;

  /// Returns a copy of this record with the given fields replaced.
  ProjectRecord copyWith({
    String? title,
    String? synopsis,
    ManuscriptStatus? status,
    String? language,
    String? orderKey,
    bool? isPublic,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return ProjectRecord(
      id: id,
      ownerId: ownerId,
      title: title ?? this.title,
      synopsis: synopsis ?? this.synopsis,
      status: status ?? this.status,
      language: language ?? this.language,
      orderKey: orderKey ?? this.orderKey,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  /// The JSON representation sent to the clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'owner_id': ownerId,
      'title': title,
      'synopsis': synopsis,
      'status': status.name,
      'language': language,
      'order_key': orderKey,
      'is_public': isPublic,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}

/// A project together with the role the caller holds on it.
final class ProjectAccess {
  /// Creates an access record.
  const ProjectAccess({required this.project, required this.role});

  /// The project.
  final ProjectRecord project;

  /// The role of the caller on the project.
  final ProjectRole role;
}
