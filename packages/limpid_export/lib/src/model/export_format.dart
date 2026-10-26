/// Formats de sortie supportes par le moteur d'export.
enum ExportFormat {
  /// EPUB 3 (lecture, vente, KDP, Leanpub).
  epub3('epub', 'application/epub+zip'),

  /// PDF reflowable (lecture, apercu).
  pdfReflowable('pdf', 'application/pdf'),

  /// PDF print-ready (KDP, IngramSpark).
  pdfPrintReady('pdf', 'application/pdf'),

  /// Document Word (manuscrits, soumissions).
  docx(
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),

  /// HTML semantique (ebook, vitrine).
  html('html', 'text/html; charset=utf-8'),

  /// Page de vente HTML (Open Graph + JSON-LD `Book`).
  htmlLanding('html', 'text/html; charset=utf-8'),

  /// Markdown (interoperabilite, git).
  markdown('md', 'text/markdown; charset=utf-8'),

  /// OpenDocument Text (LibreOffice).
  odt('odt', 'application/vnd.oasis.opendocument.text');

  const ExportFormat(this.extension, this.mimeType);

  /// Alias pratique : le PDF par defaut est la variante reflowable.
  static const ExportFormat pdf = ExportFormat.pdfReflowable;

  /// Extension de fichier, sans le point.
  final String extension;

  /// Type MIME du fichier produit.
  final String mimeType;

  /// Vrai si ce format est un PDF.
  bool get isPdf =>
      this == ExportFormat.pdfReflowable || this == ExportFormat.pdfPrintReady;
}
