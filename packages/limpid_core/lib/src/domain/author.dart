import 'ids.dart';

/// A user account of the platform.
///
/// One account equals one author (D-01): the model does not model
/// organisations.
final class Author {
  /// Creates an author.
  const Author({
    required this.id,
    required this.displayName,
    required this.email,
    this.penName,
    this.avatarUrl,
    this.createdAt,
  });

  /// Identifier of the account.
  final AuthorId id;

  /// Name displayed in the interface.
  final String displayName;

  /// Primary email address of the account.
  final String email;

  /// Public pen name, when different from [displayName].
  final String? penName;

  /// URL of the avatar image.
  final String? avatarUrl;

  /// Account creation timestamp.
  final DateTime? createdAt;

  /// The name used in public contexts.
  String get publicName => penName ?? displayName;

  /// Returns a copy of this author with the given fields replaced.
  Author copyWith({
    String? displayName,
    String? email,
    String? penName,
    String? avatarUrl,
    DateTime? createdAt,
  }) {
    return Author(
      id: id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      penName: penName ?? this.penName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Author &&
          other.id == id &&
          other.displayName == displayName &&
          other.email == email &&
          other.penName == penName &&
          other.avatarUrl == avatarUrl &&
          other.createdAt == createdAt);

  @override
  int get hashCode => Object.hash(
    Author,
    id,
    displayName,
    email,
    penName,
    avatarUrl,
    createdAt,
  );

  @override
  String toString() => 'Author($id, $publicName)';
}
