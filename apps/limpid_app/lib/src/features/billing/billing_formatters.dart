/// Les écritures des chiffres de l'écran de formule.
///
/// Les prix sont en centimes d'euro et les volumes en octets : l'écran ne
/// lit jamais l'unité brute du serveur. Les séparateurs suivent la
/// typographie française — une espace insécable entre les milliers, une
/// virgule entre la partie entière et la partie décimale.
library;

/// L'espace insécable qui sépare un nombre de son unité.
const String kNoBreakSpace = ' ';

/// Le séparateur qui joint deux mentions sur une même ligne.
///
/// C'est de la ponctuation, pas de la copie : il ne change pas avec la
/// langue de l'interface.
const String kSeparator = ' · ';

/// Les suffixes des volumes, du plus petit au plus grand.
const List<String> _byteUnits = <String>['o', 'Ko', 'Mo', 'Go', 'To'];

/// Le nombre d'octets d'un kilo-octet.
const int _kiloByte = 1024;

/// Écrit un prix en euros.
///
/// Le prix est arrondi au centime : la somme affichée est celle que
/// l'auteur paie.
String formatPrice(int cents) {
  final int units = cents ~/ 100;
  final int remainder = cents % 100;
  final String decimals = remainder.toString().padLeft(2, '0');
  return '$units,$decimals$kNoBreakSpace€';
}

/// Écrit un volume en octets.
///
/// L'unité est la plus grande qui garde un chiffre entier : « 500 Mo » se
/// lit mieux que « 524 288 000 o ».
String formatBytes(int bytes) {
  final bool isNegative = bytes < 0;
  double value = bytes.abs().toDouble();
  int unit = 0;
  while (value >= _kiloByte && unit < _byteUnits.length - 1) {
    value /= _kiloByte;
    unit++;
  }
  final String number = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1).replaceFirst('.', ',');
  final String sign = isNegative ? '-' : '';
  return '$sign$number$kNoBreakSpace${_byteUnits[unit]}';
}
