/// L'ISBN-13 d'un livre.
///
/// La classe lit un ISBN brut (avec ou sans tiret ni espace) et verifie sa
/// cle de controle.
///
/// **Le numero est celui de l'auteur.** Un ISBN-13 est employe tel quel :
/// le code-barres imprime porte le nombre que l'auteur a saisi, et rien
/// d'autre. L'edition imprimee d'un livre porte son **propre** ISBN, dans
/// la plage `979` : ce nombre n'est pas derive de l'ISBN du livre, il est
/// attribue par l'agence des ISBN. Le fabriquer serait imprimer un code
/// qui ne correspond a aucun livre enregistre.
///
/// Un ISBN-10 est converti selon la regle de l'agence : le prefixe `978`
/// precede les neuf chiffres, et la cle de controle est recalculee.
///
/// ```dart
/// final isbn = Isbn13.tryParse('978-2-1234-5678-0');
/// print(isbn?.digits); // 9782123456780
/// ```
class Isbn13 {
  /// Cree un ISBN-13 a partir de ses treize chiffres.
  const Isbn13(this.digits);

  /// Les treize chiffres de l'ISBN-13, cle de controle comprise.
  final String digits;

  /// Longueur d'un ISBN-13.
  static const int digitCount = 13;

  /// Longueur d'un ISBN-10.
  static const int legacyDigitCount = 10;

  /// Prefixe des ISBN-13 deja acquis.
  static const String bookPrefix = '978';

  /// Prefixe de l'edition imprimee, quand le livre en porte un.
  ///
  /// Ce nombre est saisi par l'auteur : il n'est jamais derive.
  static const String printPrefix = '979';

  /// Expression d'un ISBN-13 : treize chiffres.
  static final RegExp _isbn13Pattern = RegExp(r'^\d{13}$');

  /// Expression d'un ISBN-10 : neuf chiffres puis une cle.
  static final RegExp _isbn10Pattern = RegExp(r'^\d{9}[\dXx]$');

  /// Retire les tirets et les espaces d'un ISBN brut.
  static String normalize(String raw) => raw.replaceAll(RegExp(r'[\s-]'), '');

  /// Vrai quand l'ISBN brut porte une cle de controle valide.
  ///
  /// Le code est donne avec ou sans tiret ni espace : [normalize] le
  /// prepare.
  static bool isValid(String raw) => tryParse(raw) != null;

  /// Lit l'ISBN brut et renvoie son ISBN-13.
  ///
  /// Renvoie `null` quand l'ISBN est absent, mal forme ou invalide :
  /// l'absence d'ISBN n'est pas une erreur, elle signifie simplement que
  /// l'edition imprimee n'a pas encore de code a imprimer.
  static Isbn13? tryParse(String raw) {
    final digits = normalize(raw);
    if (digits.length == digitCount) {
      return _fromIsbn13(digits);
    }
    if (digits.length == legacyDigitCount) {
      return _fromIsbn10(digits);
    }
    return null;
  }

  static Isbn13? _fromIsbn13(String digits) {
    if (!_isbn13Pattern.hasMatch(digits)) {
      return null;
    }
    if (!_isValidIsbn13(digits)) {
      return null;
    }
    // Le nombre est employe tel quel : le code-barres doit porter
    // l'ISBN que l'auteur a saisi.
    return Isbn13(digits);
  }

  static Isbn13? _fromIsbn10(String digits) {
    if (!_isbn10Pattern.hasMatch(digits)) {
      return null;
    }
    if (!_isValidIsbn10(digits)) {
      return null;
    }
    // La regle de l'agence : le prefixe `978` precede les neuf chiffres.
    final body = '$bookPrefix${digits.substring(0, legacyDigitCount - 1)}';
    return Isbn13('$body${checkDigitOf(body)}');
  }

  /// Calcule la cle de controle d'un EAN-13 a partir de ses douze
  /// premiers chiffres.
  ///
  /// Les positions impaires (a partir de zero) sont ponderees de un, les
  /// positions paires de trois.
  static String checkDigitOf(String body) {
    var sum = 0;
    for (var index = 0; index < body.length; index++) {
      final digit = int.parse(body[index]);
      sum += index.isEven ? digit : digit * 3;
    }
    return '${(10 - (sum % 10)) % 10}';
  }

  /// Vrai quand les treize chiffres portent une cle de controle valide.
  static bool _isValidIsbn13(String digits) {
    final body = digits.substring(0, digitCount - 1);
    return digits.substring(digitCount - 1) == checkDigitOf(body);
  }

  /// Vrai quand les dix chiffres portent une cle de controle valide.
  ///
  /// La cle d'un ISBN-10 est la lettre `X` quand elle vaut dix.
  static bool _isValidIsbn10(String digits) {
    var sum = 0;
    for (var index = 0; index < legacyDigitCount; index++) {
      final character = digits[index];
      final value = character.toUpperCase() == 'X'
          ? 10
          : int.tryParse(character) ?? -1;
      if (value < 0) {
        return false;
      }
      sum += value * (legacyDigitCount - index);
    }
    return sum % 11 == 0;
  }

  @override
  String toString() => 'Isbn13($digits)';
}
