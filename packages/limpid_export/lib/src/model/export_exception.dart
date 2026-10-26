/// Exception typee des exports Limpid.
///
/// Le [message] est destine a l'utilisateur (francais), le [code] est un
/// identifiant technique stable, destine aux journaux et aux tests.
class ExportException implements Exception {
  /// Cree une erreur d'export.
  const ExportException(this.code, this.message, {this.cause, this.details});

  /// Code technique stable (par exemple `epub.empty_book`).
  final String code;

  /// Message utilisateur, en francais.
  final String message;

  /// Cause technique d'origine, si elle existe.
  final Object? cause;

  /// Details techniques complementaires (jamais destinees a l'utilisateur).
  final Map<String, String>? details;

  @override
  String toString() => 'ExportException($code): $message';
}
