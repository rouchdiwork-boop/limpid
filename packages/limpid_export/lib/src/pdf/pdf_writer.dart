import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../fonts/font_registry.dart';
import '../model/export_book.dart';
import '../model/export_options.dart';
import '../util/file_name.dart';
import 'pdf_cover_fonts.dart';
import 'pdf_fonts.dart';
import 'pdf_geometry.dart';
import 'pdf_page_content.dart';
import 'pdf_paginator.dart';
import 'pdf_text_measure.dart';
import 'pdf_typography.dart';

/// Generateur PDF.
///
/// Deux modes sont pris en charge :
/// - reflowable : pagination automatique, titre courant et numeros de page ;
/// - print-ready : format impose, marges en miroir, fond perdu.
class PdfWriter {
  /// Cree un generateur PDF.
  ///
  /// [fontRegistry] fournit les polices embarquees ; sans registre, le
  /// moteur lit les faces livrees avec le paquet `limpid_export`, et
  /// retombe sur ses polices de substitution si elles sont absentes.
  /// [onWarning] collecte les avertissements non bloquants.
  const PdfWriter({this.fontRegistry, this.onWarning});

  /// Registre des polices embarquees.
  final FontRegistry? fontRegistry;

  /// Collecteur d'avertissements.
  final void Function(String message)? onWarning;

  /// Type MIME du fichier produit.
  static const String mimeType = 'application/pdf';

  /// Serialise le livre et renvoie les octets du PDF.
  Future<Uint8List> write(ExportBook book, ExportOptions options) async {
    final registry = fontRegistry ?? FontRegistry.packageAssets();
    final fonts = await PdfFontSet.resolve(registry, options.fontFamily);
    for (final warning in fonts.warnings()) {
      onWarning?.call(warning);
    }

    final geometry = PdfPageGeometry.fromOptions(options);
    final typography = PdfTypography(options);
    final measure = PdfTextMeasure(fonts);
    final paginator = PdfPaginator(
      geometry: geometry,
      typography: typography,
      measure: measure,
      fonts: fonts,
      options: options,
      onWarning: onWarning,
    );

    final pagination = paginator.paginate(book);
    final coverFonts = await PdfCoverFonts.resolve(registry);
    final document = pw.Document(
      title: book.title,
      author: book.authors.isEmpty ? null : book.authors.join(', '),
      subject: book.metadata.description,
      creator: 'Limpid',
      producer: 'Limpid export',
    );

    for (final page in pagination.pages) {
      document.addPage(
        _buildPage(
          page,
          book,
          pagination,
          geometry,
          fonts,
          coverFonts,
          options,
        ),
      );
    }

    _addOutline(document, book, pagination);
    _addDestinations(document, book, pagination);

    return document.save();
  }

  void _addOutline(
    pw.Document document,
    ExportBook book,
    PdfPaginationResult pagination,
  ) {
    final pages = document.document.pdfPageList.pages;
    for (var index = 0; index < book.chapters.length; index++) {
      final pageIndex = pagination.chapterPageNumbers[index] - 1;
      if (pageIndex < 0 || pageIndex >= pages.length) {
        continue;
      }
      document.document.outline.add(
        PdfOutline(
          document.document,
          title: book.chapters[index].title,
          dest: pages[pageIndex],
        ),
      );
    }
  }

  /// Declare les destinations internes des chapitres (sommaire cliquable).
  void _addDestinations(
    pw.Document document,
    ExportBook book,
    PdfPaginationResult pagination,
  ) {
    final pages = document.document.pdfPageList.pages;
    for (var index = 0; index < book.chapters.length; index++) {
      final pageIndex = pagination.chapterPageNumbers[index] - 1;
      if (pageIndex < 0 || pageIndex >= pages.length) {
        continue;
      }
      document.document.pdfNames.addDest(
        chapterDestination(index),
        pages[pageIndex],
      );
    }
  }

  pw.Page _buildPage(
    PdfPageContent page,
    ExportBook book,
    PdfPaginationResult pagination,
    PdfPageGeometry geometry,
    PdfFontSet fonts,
    PdfCoverFonts coverFonts,
    ExportOptions options,
  ) {
    final children = <pw.Widget>[];
    final bodyFont = fonts.regular;

    final cover = page.cover;
    if (cover != null) {
      final widget = cover.cover.build(
        fonts: coverFonts,
        onWarning: onWarning ?? _ignoreWarning,
      );
      if (widget != null) {
        children.add(
          pw.Positioned(
            left: cover.left,
            top: cover.top,
            child: pw.SizedBox(
              width: cover.width,
              height: cover.height,
              child: widget,
            ),
          ),
        );
      }
    }

    if (options.includeRunningHeader && page.chapterIndex >= 0) {
      final header = page.isEven
          ? book.title
          : pagination.chapterTitles[page.chapterIndex];
      children.add(
        pw.Positioned(
          left: geometry.contentLeft(page.isEven),
          top: geometry.headerBaseline(),
          child: pw.Text(
            header,
            style: pw.TextStyle(
              font: bodyFont.widget,
              fontSize: options.fontSize * 0.78,
            ),
          ),
        ),
      );
    }

    if (options.includePageNumbers && page.chapterIndex >= 0) {
      final label = '${page.pageNumber}';
      final labelWidth =
          bodyFont.metric.stringMetrics(label).width * options.fontSize * 0.85;
      final contentWidth = geometry.contentWidth(page.isEven);
      children.add(
        pw.Positioned(
          left:
              geometry.contentLeft(page.isEven) +
              (contentWidth - labelWidth) / 2,
          top: geometry.footerBaseline(),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: bodyFont.widget,
              fontSize: options.fontSize * 0.85,
            ),
          ),
        ),
      );
    }

    for (final run in page.texts) {
      final text = pw.Text(
        run.text,
        style: pw.TextStyle(
          font: run.font.widget,
          fontSize: run.fontSize,
          wordSpacing: run.wordSpacing,
        ),
      );
      final destination = run.linkDestination;
      children.add(
        pw.Positioned(
          left: run.left,
          top: run.top,
          child: destination == null
              ? text
              : pw.Link(destination: destination, child: text),
        ),
      );
    }

    for (final image in page.images) {
      final widget = _buildImage(image);
      if (widget == null) {
        continue;
      }
      children.add(
        pw.Positioned(left: image.left, top: image.top, child: widget),
      );
    }

    final barcode = page.barcode;
    if (barcode != null) {
      children.add(
        pw.Positioned(
          left: barcode.left,
          top: barcode.top,
          child: barcode.barcode.build(),
        ),
      );
    }

    return pw.Page(
      pageFormat: PdfPageFormat(page.pageWidth, page.pageHeight),
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Stack(children: children),
    );
  }

  /// Absorbe un avertissement quand aucun collecteur n'est fourni.
  static void _ignoreWarning(String message) {}

  pw.Widget? _buildImage(PdfImageRun image) {
    try {
      return pw.Image(
        pw.MemoryImage(image.bytes),
        width: image.width,
        height: image.height,
      );
    } on Object catch (error) {
      onWarning?.call('Illustration ignoree : format non lisible ($error).');
      return null;
    }
  }

  /// Nom de fichier recommande pour l'export PDF.
  static String fileNameFor(ExportBook book) =>
      FileNames.forBook(book.title, 'pdf');
}
