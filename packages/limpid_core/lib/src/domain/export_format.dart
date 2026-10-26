/// The export formats supported by Limpid (D-09).
enum ExportFormat {
  /// EPUB 3, for sale (KDP, Leanpub).
  epub3,

  /// Reflowable PDF, for reading and preview.
  pdfReflowable,

  /// Print-ready PDF with bleed and page numbers (KDP, IngramSpark).
  pdfPrintReady,

  /// Microsoft Word document.
  docx,

  /// Standalone HTML page, for the public showcase.
  html,

  /// Markdown text file.
  markdown,

  /// OpenDocument text file.
  odt,

  /// Kindle package format, for direct KDP upload.
  kindleKpf,
}

/// The MIME type produced for each export format.
String mimeTypeOf(ExportFormat format) => switch (format) {
  ExportFormat.epub3 => 'application/epub+zip',
  ExportFormat.pdfReflowable || ExportFormat.pdfPrintReady => 'application/pdf',
  ExportFormat.docx =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ExportFormat.html => 'text/html',
  ExportFormat.markdown => 'text/markdown',
  ExportFormat.odt => 'application/vnd.oasis.opendocument.text',
  ExportFormat.kindleKpf => 'application/octet-stream',
};

/// The file extension (without the dot) produced for each export format.
extension ExportFormatFileExtension on ExportFormat {
  /// The canonical file extension for this format.
  String get fileExtension => switch (this) {
    ExportFormat.epub3 => 'epub',
    ExportFormat.pdfReflowable || ExportFormat.pdfPrintReady => 'pdf',
    ExportFormat.docx => 'docx',
    ExportFormat.html => 'html',
    ExportFormat.markdown => 'md',
    ExportFormat.odt => 'odt',
    ExportFormat.kindleKpf => 'kpf',
  };
}

/// Whether the format is a print-oriented layout.
extension ExportFormatPrintability on ExportFormat {
  /// Whether this format targets print production.
  bool get isPrintReady =>
      this == ExportFormat.pdfPrintReady || this == ExportFormat.kindleKpf;
}
