import 'package:limpid_core/src/internal/collections.dart';

import 'ids.dart';

/// A location of the story bible (O2).
final class Place {
  /// Creates a place sheet.
  const Place({
    required this.id,
    required this.name,
    this.kind = '',
    this.description = '',
    this.atmosphere = '',
    this.significance = '',
    this.notes = '',
    this.relatedCharacterIds = const <CharacterId>[],
    this.createdAt,
    this.updatedAt,
  });

  /// Identifier of the place.
  final PlaceId id;

  /// Name of the place.
  final String name;

  /// Kind of place (city, house, ship, region…).
  final String kind;

  /// Description of the place.
  final String description;

  /// Atmosphere / mood of the place.
  final String atmosphere;

  /// Narrative significance of the place.
  final String significance;

  /// Free-form notes.
  final String notes;

  /// Identifiers of characters present in this place.
  final List<CharacterId> relatedCharacterIds;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last modification timestamp.
  final DateTime? updatedAt;

  /// Returns a copy of this place with the given fields replaced.
  Place copyWith({
    String? name,
    String? kind,
    String? description,
    String? atmosphere,
    String? significance,
    String? notes,
    List<CharacterId>? relatedCharacterIds,
    DateTime? updatedAt,
  }) {
    return Place(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      description: description ?? this.description,
      atmosphere: atmosphere ?? this.atmosphere,
      significance: significance ?? this.significance,
      notes: notes ?? this.notes,
      relatedCharacterIds: relatedCharacterIds ?? this.relatedCharacterIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Place &&
          other.id == id &&
          other.name == name &&
          other.kind == kind &&
          other.description == description &&
          other.atmosphere == atmosphere &&
          other.significance == significance &&
          other.notes == notes &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          listEquals(other.relatedCharacterIds, relatedCharacterIds));

  @override
  int get hashCode => Object.hash(
    Place,
    id,
    name,
    kind,
    description,
    atmosphere,
    significance,
    notes,
    createdAt,
    updatedAt,
    Object.hashAll(relatedCharacterIds),
  );

  @override
  String toString() => 'Place($id, $name)';
}
