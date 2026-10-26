/// A feature flag of the back-office.
///
/// The flag is read at every call: activating it does not require a
/// redeployment of the server, and the change is visible at once.
final class FeatureFlag {
  /// Creates a feature flag.
  const FeatureFlag({
    required this.key,
    required this.isEnabled,
    required this.description,
    required this.updatedAt,
    required this.updatedBy,
  });

  /// The technical key of the indicator, for example `ai_premium`.
  final String key;

  /// Whether the indicator is active.
  final bool isEnabled;

  /// What the indicator does, in one sentence.
  final String description;

  /// The moment of the last change of the indicator.
  final DateTime updatedAt;

  /// The identifier of the administrator who changed the indicator.
  final String updatedBy;

  /// A copy of the flag with the given fields replaced.
  ///
  /// The absent fields keep the value they had: the copy never loses a
  /// value it was not asked to change.
  FeatureFlag copyWith({
    bool? isEnabled,
    String? description,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return FeatureFlag(
      key: key,
      isEnabled: isEnabled ?? this.isEnabled,
      description: description ?? this.description,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
