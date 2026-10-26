import 'isbn13.dart';

/// Le symbole EAN-13 : les modules qui encodent treize chiffres.
///
/// La structure est celle de la norme EAN-13 :
///
/// - un garde a gauche (`101`) ;
/// - six chiffres a gauche du centre, encodes en `L` ou en `G` selon la
///   parite imposee par le premier chiffre ;
/// - un garde central (`01010`) ;
/// - six chiffres a droite, encodes en `R` ;
/// - un garde a droite (`101`).
///
/// Le symbole compte 95 modules ; les zones de silence l'entourent (11
/// modules a gauche, 7 a droite), soit 113 modules au total.
///
/// ```dart
/// final symbol = Ean13.tryParse('978-2-1234-5678-0');
/// print(symbol?.modules.length); // 95
/// ```
class Ean13 {
  /// Cree un symbole a partir de ses treize chiffres et de ses modules.
  const Ean13({required this.digits, required this.modules});

  /// Construit le symbole d'un EAN-13 valide.
  ///
  /// Leve une [FormatException] quand les chiffres sont mal formes ou
  /// quand la cle de controle est fausse : un symbole invalide ne doit
  /// jamais etre imprime.
  factory Ean13.fromDigits(String digits) {
    if (!RegExp(r'^\d{13}$').hasMatch(digits)) {
      throw FormatException('EAN-13 invalide : $digits', digits);
    }
    final body = digits.substring(0, 12);
    if (Isbn13.checkDigitOf(body) != digits.substring(12)) {
      throw FormatException('EAN-13 invalide : $digits', digits);
    }
    return Ean13(digits: digits, modules: _encode(digits));
  }

  /// Les treize chiffres encodes, cle de controle comprise.
  final String digits;

  /// Les 95 modules du symbole : `true` pour une barre, `false` pour un
  /// espace.
  final List<bool> modules;

  /// Nombre de modules du symbole.
  static const int moduleCount = 95;

  /// Modules de la zone de silence a gauche du symbole.
  static const int leftQuietZone = 11;

  /// Modules de la zone de silence a droite du symbole.
  static const int rightQuietZone = 7;

  /// Modules du symbole, zones de silence comprises.
  static const int totalWidth = moduleCount + leftQuietZone + rightQuietZone;

  /// Position du premier module du garde de gauche.
  static const int leftGuardStart = 0;

  /// Position du premier module du garde central.
  static const int centerGuardStart = 45;

  /// Position du premier module du garde de droite.
  static const int rightGuardStart = 92;

  /// Nombre de modules d'un garde.
  static const int guardLength = 3;

  /// Nombre de modules du garde central.
  static const int centerGuardLength = 5;

  /// Nombre de modules encodes par un chiffre.
  static const int digitModules = 7;

  /// Encodage `L` (parite impaire) des chiffres de gauche.
  static const List<String> _leftOdd = <String>[
    '0001101',
    '0011001',
    '0010011',
    '0111101',
    '0100011',
    '0110001',
    '0101111',
    '0111011',
    '0110111',
    '0001011',
  ];

  /// Encodage `G` (parite paire) des chiffres de gauche.
  static const List<String> _leftEven = <String>[
    '0100111',
    '0110011',
    '0011011',
    '0100001',
    '0011101',
    '0111001',
    '0000101',
    '0010001',
    '0001001',
    '0010111',
  ];

  /// Encodage `R` des chiffres de droite.
  static const List<String> _right = <String>[
    '1110010',
    '1100110',
    '1101100',
    '1000010',
    '1011100',
    '1001110',
    '1010000',
    '1000100',
    '1001000',
    '1110100',
  ];

  /// Parite des six chiffres de gauche, selon le premier chiffre.
  static const List<String> _parity = <String>[
    'LLLLLL',
    'LLGLGG',
    'LLGGLG',
    'LLGGGL',
    'LGLLGG',
    'LGGLLG',
    'LGGGLL',
    'LGLGLG',
    'LGLGGL',
    'LGGLGL',
  ];

  /// Lit un ISBN et renvoie le symbole EAN-13 correspondant.
  ///
  /// Renvoie `null` quand l'ISBN est absent ou invalide : le code-barres
  /// est alors simplement omis.
  static Ean13? tryParse(String isbn) {
    final parsed = Isbn13.tryParse(isbn);
    if (parsed == null) {
      return null;
    }
    return Ean13.fromDigits(parsed.digits);
  }

  static List<bool> _encode(String digits) {
    final modules = <bool>[];
    modules.addAll(_pattern('101'));
    final parity = _parity[int.parse(digits[0])];
    for (var index = 0; index < 6; index++) {
      final digit = int.parse(digits[index + 1]);
      final table = parity[index] == 'L' ? _leftOdd : _leftEven;
      modules.addAll(_pattern(table[digit]));
    }
    modules.addAll(_pattern('01010'));
    for (var index = 0; index < 6; index++) {
      final digit = int.parse(digits[index + 7]);
      modules.addAll(_pattern(_right[digit]));
    }
    modules.addAll(_pattern('101'));
    return List<bool>.unmodifiable(modules);
  }

  static List<bool> _pattern(String bits) =>
      bits.split('').map((bit) => bit == '1').toList(growable: false);

  /// Les barres du symbole, groupees en suites contigues.
  ///
  /// Chaque suite donne le premier module (parmi les 95) et le nombre de
  /// modules qui la composent : c'est la forme que le rendu PDF consomme.
  List<Ean13Run> get runs {
    final result = <Ean13Run>[];
    var start = -1;
    for (var index = 0; index < modules.length; index++) {
      final isBar = modules[index];
      if (isBar && start < 0) {
        start = index;
      } else if (!isBar && start >= 0) {
        result.add(Ean13Run(start: start, length: index - start));
        start = -1;
      }
    }
    if (start >= 0) {
      result.add(Ean13Run(start: start, length: modules.length - start));
    }
    return List<Ean13Run>.unmodifiable(result);
  }

  @override
  String toString() => 'Ean13($digits)';
}

/// Une suite de barres contigues d'un symbole EAN-13.
class Ean13Run {
  /// Cree une suite de barres.
  const Ean13Run({required this.start, required this.length});

  /// Premier module de la suite.
  final int start;

  /// Nombre de modules de la suite.
  final int length;

  @override
  String toString() => 'Ean13Run($start, $length)';
}
