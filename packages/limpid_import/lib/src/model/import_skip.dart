/// Une categorie de contenu que l'import a laisse de cote.
///
/// L'import annonce ses limites : il ne cache jamais ce qu'il n'a pas
/// importe. Chaque categorie porte le nombre d'elements rencontres.
final class ImportSkip {
  /// Cree une categorie d'elements laisses de cote.
  const ImportSkip({required this.reason, required this.count});

  /// La raison technique de l'abandon, par exemple `images`.
  final String reason;

  /// Le nombre d'elements concernes.
  final int count;

  /// Le nom de la raison, dans le vocabulaire de l'API.
  String get label => reason;

  /// Une copie de l'element avec le compte remplace.
  ImportSkip copyWith({String? reason, int? count}) {
    return ImportSkip(
      reason: reason ?? this.reason,
      count: count ?? this.count,
    );
  }

  @override
  String toString() => 'ImportSkip($reason, $count)';
}
