/// Moteur d'export de livres de Limpid.
///
/// Generateurs natifs Dart, hors-ligne, sans service externe : EPUB 3, PDF
/// (reflowable et print-ready), DOCX, HTML, Markdown et ODT.
///
/// Le package ne depend pas de `limpid_core` : il expose son propre modele
/// d'entree intermediaire ([ExportBook]) que l'application traduit depuis
/// son modele interne.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'src/docx/docx_writer.dart';
import 'src/epub/epub3_writer.dart';
import 'src/fonts/font_registry.dart';
import 'src/html/html_sales_page.dart';
import 'src/html/html_writer.dart';
import 'src/markdown/markdown_writer.dart';
import 'src/model/export_book.dart';
import 'src/model/export_exception.dart';
import 'src/model/export_format.dart';
import 'src/model/export_options.dart';
import 'src/model/export_result.dart';
import 'src/odt/odt_writer.dart';
import 'src/pdf/pdf_writer.dart';

export 'src/barcode/ean13.dart';
export 'src/barcode/isbn13.dart';
export 'src/cover/cover_color.dart';
export 'src/cover/cover_exporter.dart';
export 'src/cover/cover_generator.dart';
export 'src/cover/cover_geometry.dart';
export 'src/cover/cover_image.dart';
export 'src/cover/cover_palette.dart';
export 'src/cover/cover_svg_format.dart';
export 'src/cover/cover_svg_panels.dart';
export 'src/cover/cover_svg_writer.dart';
export 'src/cover/cover_text_metrics.dart';
export 'src/cover/cover_tokens.dart';
export 'src/cover/cover_typography.dart';
export 'src/cover/cover_variant.dart';
export 'src/docx/docx_writer.dart';
export 'src/epub/epub3_writer.dart';
export 'src/epub/epub_package.dart';
export 'src/fonts/embedded_font.dart';
export 'src/fonts/font_registry.dart';
export 'src/fonts/package_font_loader.dart';
export 'src/html/html_sales_page.dart';
export 'src/html/html_styles.dart';
export 'src/html/html_writer.dart';
export 'src/markdown/markdown_writer.dart';
export 'src/model/export_block.dart';
export 'src/model/export_block_type.dart';
export 'src/model/export_book.dart';
export 'src/model/export_chapter.dart';
export 'src/model/export_exception.dart';
export 'src/model/export_format.dart';
export 'src/model/export_image.dart';
export 'src/model/export_metadata.dart';
export 'src/model/export_options.dart';
export 'src/model/export_result.dart';
export 'src/odt/odt_writer.dart';
export 'src/pdf/pdf_barcode.dart';
export 'src/pdf/pdf_document.dart';
export 'src/pdf/pdf_writer.dart';

/// Point d'entree du moteur d'export.
///
/// ```dart
/// final exporter = LimpidExporter();
/// final result = await exporter.export(
///   ExportFormat.epub3,
///   book,
///   const ExportOptions(),
/// );
/// ```
class LimpidExporter {
  /// Cree un exportateur.
  ///
  /// [fontRegistry] permet d'injecter les polices embarquees de
  /// l'application (par exemple via `rootBundle.load`) ; sans registre, le
  /// generateur PDF lit les faces livrees avec le paquet `limpid_export`, et
  /// retombe sur ses polices de substitution si elles sont absentes.
  const LimpidExporter({this.fontRegistry});

  /// Registre des polices embarquees.
  final FontRegistry? fontRegistry;

  /// Exporte un livre dans le format demande.
  ///
  /// Leve une [ExportException] en cas d'echec ; les anomalies non
  /// bloquantes sont renvoyees dans [ExportResult.warnings].
  Future<ExportResult> export(
    ExportFormat format,
    ExportBook book,
    ExportOptions options,
  ) async {
    final warnings = <String>[];
    try {
      final bytes = await _write(format, book, options, warnings);
      return ExportResult(
        bytes: bytes,
        fileName: fileNameFor(format, book),
        mimeType: format.mimeType,
        warnings: List<String>.unmodifiable(warnings),
      );
    } on ExportException {
      rethrow;
    } on Object catch (error) {
      throw ExportException(
        'export.${format.name}.failed',
        "L'export ${format.name} a echoue.",
        cause: error,
      );
    }
  }

  Future<Uint8List> _write(
    ExportFormat format,
    ExportBook book,
    ExportOptions options,
    List<String> warnings,
  ) async {
    switch (format) {
      case ExportFormat.epub3:
        return const Epub3Writer().write(book, options);
      case ExportFormat.pdfReflowable:
        return PdfWriter(
          fontRegistry: fontRegistry,
          onWarning: warnings.add,
        ).write(book, options.copyWith(pdfMode: ExportPdfMode.reflowable));
      case ExportFormat.pdfPrintReady:
        return PdfWriter(
          fontRegistry: fontRegistry,
          onWarning: warnings.add,
        ).write(book, options.copyWith(pdfMode: ExportPdfMode.printReady));
      case ExportFormat.docx:
        return const DocxWriter().write(book, options);
      case ExportFormat.html:
        return const HtmlWriter().write(book, options);
      case ExportFormat.htmlLanding:
        final content = const HtmlSalesPageWriter().render(book, options);
        return Uint8List.fromList(utf8.encode(content));
      case ExportFormat.markdown:
        return const MarkdownWriter().write(book, options);
      case ExportFormat.odt:
        return const OdtWriter().write(book, options);
    }
  }

  /// Nom de fichier recommande pour un export.
  static String fileNameFor(ExportFormat format, ExportBook book) {
    switch (format) {
      case ExportFormat.epub3:
        return Epub3Writer.fileNameFor(book);
      case ExportFormat.pdfReflowable:
      case ExportFormat.pdfPrintReady:
        return PdfWriter.fileNameFor(book);
      case ExportFormat.docx:
        return DocxWriter.fileNameFor(book);
      case ExportFormat.html:
        return HtmlWriter.fileNameFor(book);
      case ExportFormat.htmlLanding:
        return HtmlSalesPageWriter.fileNameFor(book);
      case ExportFormat.markdown:
        return MarkdownWriter.fileNameFor(book);
      case ExportFormat.odt:
        return OdtWriter.fileNameFor(book);
    }
  }
}
