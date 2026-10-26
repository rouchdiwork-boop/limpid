import 'package:limpid_core/src/internal/collections.dart';

import 'ids.dart';

/// A character of the story bible (O2 / O3).
final class Character {
  /// Creates a character sheet.
  const Character({
    required this.id,
    required this.name,
    this.aliases = const <String>[],
    this.role = '',
    this.physicalDescription = '',
    this.personality = '',
    this.voice = '',
    this.backstory = '',
    this.secrets = '',
    this.notes = '',
    this.appearanceIds = const <String>[],
    this.relatedCharacterIds = const <CharacterId>[],
    this.createdAt,
    this.updatedAt,
  });

  /// Identifier of the character.
  final CharacterId id;

  /// Name of the character.
  final String name;

  /// Alternative names or nicknames.
  final List<String> aliases;

  /// Narrative role (protagonist, antagonist, mentor…).
  final String role;

  /// Physical description.
  final String physicalDescription;

  /// Personality summary.
  final String personality;

  /// Description of the voice / speech style.
  final String voice;

  /// Backstory summary.
  final String backstory;

  /// Secrets known to the character.
  final String secrets;

  /// Free-form notes.
  final String notes;

  /// Identifiers of the appearance events of this character.
  final List<String> appearanceIds;

  /// Identifiers of related characters.
  final List<CharacterId> relatedCharacterIds;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last modification timestamp.
  final DateTime? updatedAt;

  /// Returns a copy of this character with the given fields replaced.
  Character copyWith({
    String? name,
    List<String>? aliases,
    String? role,
    String? physicalDescription,
    String? personality,
    String? voice,
    String? backstory,
    String? secrets,
    String? notes,
    List<String>? appearanceIds,
    List<CharacterId>? relatedCharacterIds,
    DateTime? updatedAt,
  }) {
    return Character(
      id: id,
      name: name ?? this.name,
      aliases: aliases ?? this.aliases,
      role: role ?? this.role,
      physicalDescription: physicalDescription ?? this.physicalDescription,
      personality: personality ?? this.personality,
      voice: voice ?? this.voice,
      backstory: backstory ?? this.backstory,
      secrets: secrets ?? this.secrets,
      notes: notes ?? this.notes,
      appearanceIds: appearanceIds ?? this.appearanceIds,
      relatedCharacterIds: relatedCharacterIds ?? this.relatedCharacterIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Character &&
          other.id == id &&
          other.name == name &&
          other.role == role &&
          other.physicalDescription == physicalDescription &&
          other.personality == personality &&
          other.voice == voice &&
          other.backstory == backstory &&
          other.secrets == secrets &&
          other.notes == notes &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          listEquals(other.aliases, aliases) &&
          listEquals(other.appearanceIds, appearanceIds) &&
          listEquals(other.relatedCharacterIds, relatedCharacterIds));

  @override
  int get hashCode => Object.hash(
    Character,
    id,
    name,
    role,
    physicalDescription,
    personality,
    voice,
    backstory,
    secrets,
    notes,
    createdAt,
    updatedAt,
    Object.hashAll(aliases),
    Object.hashAll(appearanceIds),
    Object.hashAll(relatedCharacterIds),
  );

  @override
  String toString() => 'Character($id, $name)';
}
