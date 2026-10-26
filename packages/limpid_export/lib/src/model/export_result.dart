import 'dart:typed_data';

/// Resultat d'un export : le fichier produit et ses avertissements.
class ExportResult {
  /// Cree un resultat d'export.
  const ExportResult({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.warnings = const <String>[],
  });

  /// Contenu du fichier produit.
  final Uint8List bytes;

  /// Nom de fichier recommande, extension comprise.
  final String fileName;

  /// Type MIME du fichier produit.
  final String mimeType;

  /// Avertissements non bloquants (police de substitution, image ignoree...).
  final List<String> warnings;

  /// Taille du fichier produit, en octets.
  int get sizeInBytes => bytes.length;

  @override
  String toString() => 'ExportResult($fileName, $mimeType, ${bytes.length} o)';
}
