/// L'echec d'un import.
///
/// L'exception porte un code technique stable et un message francais destine
/// a l'auteur : elle ne dit jamais ce que le fichier contient.
final class ImportException implements Exception {
  /// Cree un echec d'import.
  const ImportException(this.code, this.message, {this.cause});

  /// Le code technique de l'echec.
  final String code;

  /// Le message de l'echec, en francais.
  final String message;

  /// L'erreur d'origine, conservee pour le journal du serveur.
  final Object? cause;

  @override
  String toString() => 'ImportException($code): $message';
}

/// Les codes techniques des echecs d'import.
abstract final class ImportErrorCodes {
  /// Le format du fichier n'est pas reconnu.
  static const String unsupportedFormat = 'import.unsupported_format';

  /// Le fichier est illisible ou corrompu.
  static const String unreadable = 'import.unreadable';

  /// Le fichier ne porte aucun texte importable.
  static const String empty = 'import.empty';
}
