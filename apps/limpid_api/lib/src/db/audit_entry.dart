/// An entry of the audit journal.
///
/// The audit journal records the sensitive actions: export, sharing,
/// deletion and plan change (D-19).
final class AuditEntry {
  /// Creates an audit entry.
  const AuditEntry({
    required this.userId,
    required this.action,
    required this.targetType,
    required this.targetId,
    this.metadata = const <String, Object?>{},
    this.ip,
    this.createdAt,
  });

  /// The account that performed the action.
  final String userId;

  /// The technical name of the action, for example `export.requested`.
  final String action;

  /// The kind of the targeted resource, for example `project`.
  final String targetType;

  /// The identifier of the targeted resource.
  final String targetId;

  /// Additional, non sensitive context of the action.
  final Map<String, Object?> metadata;

  /// The IP address of the caller.
  final String? ip;

  /// The moment of the action.
  final DateTime? createdAt;

  /// The JSON representation sent to the clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'user_id': userId,
      'action': action,
      'target_type': targetType,
      'target_id': targetId,
      'metadata': metadata,
      'ip': ip,
      'created_at': createdAt?.toUtc().toIso8601String(),
    };
  }
}
