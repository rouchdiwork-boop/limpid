/// La lecture de l'ISBN d'une publication.
///
/// Amazon exige un ISBN valide pour l'édition imprimée : le code porte une
/// clé de contrôle, en dix ou en treize chiffres. Le fichier prépare
/// porte l'ISBN sans tiret ni espace : c'est la forme que la fiche produit
/// attend.
abstract final class KdpIsbn {
  /// Normalise [raw] en ISBN sans tiret ni espace.
  static String normalize(String raw) => raw.replaceAll(RegExp(r'[\s-]'), '');

  /// Vrai quand [isbn] porte une clé de contrôle valide.
  ///
  /// Le code est donné sans tiret ni espace : [normalize] le prépare.
  static bool isValid(String isbn) {
    if (isbn.length == 13) return _isValidIsbn13(isbn);
    if (isbn.length == 10) return _isValidIsbn10(isbn);
    return false;
  }

  static final RegExp _isbn13 = RegExp(r'^\d{13}$');

  static final RegExp _isbn10 = RegExp(r'^\d{9}[\dXx]$');

  static bool _isValidIsbn13(String isbn) {
    if (!_isbn13.hasMatch(isbn)) return false;
    var sum = 0;
    for (var index = 0; index < 12; index++) {
      final int digit = int.parse(isbn[index]);
      sum += index.isEven ? digit : digit * 3;
    }
    final int check = (10 - (sum % 10)) % 10;
    return check == int.parse(isbn[12]);
  }

  static bool _isValidIsbn10(String isbn) {
    if (!_isbn10.hasMatch(isbn)) return false;
    var sum = 0;
    for (var index = 0; index < 10; index++) {
      final String character = isbn[index];
      final int value = character.toUpperCase() == 'X'
          ? 10
          : int.parse(character);
      sum += value * (10 - index);
    }
    return sum % 11 == 0;
  }
}
