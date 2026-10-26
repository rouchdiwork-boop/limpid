import '../model/export_block.dart';
import '../model/export_book.dart';
import '../model/export_chapter.dart';
import '../model/export_image.dart';
import '../model/export_options.dart';
import '../util/image_size.dart';
import 'pdf_fonts.dart';
import 'pdf_geometry.dart';
import 'pdf_page_content.dart';
import 'pdf_page_draft.dart';
import 'pdf_text_measure.dart';
import 'pdf_toc.dart';
import 'pdf_typography.dart';

/// Pagination d'un livre en pages PDF.
///
/// Le paginationneur ne connait pas le moteur PDF : il produit une liste de
/// pages dont le contenu est deja positionne. Le rendu effectif est fait par
/// le redacteur.
class PdfPaginator {
  /// Cree un paginationneur.
  PdfPaginator({
    required this.geometry,
    required this.typography,
    required this.measure,
    required this.fonts,
    required this.options,
  });

  /// Geometrie des pages.
  final PdfPageGeometry geometry;

  /// Typographie.
  final PdfTypography typography;

  /// Mesure du texte.
  final PdfTextMeasure measure;

  /// Polices utilisees.
  final PdfFontSet fonts;

  /// Options d'export.
  final ExportOptions options;

  /// Paginationne le livre.
  PdfPaginationResult paginate(ExportBook book) {
    final state = PdfPaginationState(geometry);
    final chapterStarts = <int>[];

    for (var index = 0; index < book.chapters.length; index++) {
      final chapter = book.chapters[index];
      state.startPage(chapterIndex: index);
      chapterStarts.add(state.drafts.length - 1);
      _addChapter(state, chapter, index);
    }

    final frontMatter = options.includeTitlePage ? 1 : 0;
    final tocPages = _paginateToc(book, chapterStarts, frontMatter);

    final offset = frontMatter + tocPages.length;
    final pages = <PdfPageContent>[];
    if (options.includeTitlePage) {
      pages.add(_titlePage(book));
    }
    pages.addAll(tocPages);
    pages.addAll(
      state.pages.map((page) => page.withPageNumber(offset + page.pageNumber)),
    );

    final chapterPageNumbers = <int>[
      for (var index = 0; index < chapterStarts.length; index++)
        offset + chapterStarts[index] + 1,
    ];

    return PdfPaginationResult(
      pages: pages,
      chapterPageNumbers: chapterPageNumbers,
      chapterTitles: <String>[
        for (final chapter in book.chapters) chapter.title,
      ],
    );
  }

  PdfPageContent _titlePage(ExportBook book) {
    const isEven = false;
    final contentWidth = geometry.contentWidth(isEven);
    final contentLeft = geometry.contentLeft(isEven);
    final center = contentLeft + contentWidth / 2;
    final titleSize = options.fontSize * 2.1;
    final subtitleSize = options.fontSize * 1.25;
    final authorSize = options.fontSize * 1.05;

    final texts = <PdfTextRun>[];
    var y = geometry.contentTop() + geometry.contentHeight() * 0.28;

    final titleFont = fonts.select(isBold: true, isItalic: false);
    for (final line in measure.wrap(
      book.title,
      titleFont,
      titleSize,
      contentWidth * 0.86,
    )) {
      final lineWidth = measure.widthOf(line.text, titleFont, titleSize);
      texts.add(
        PdfTextRun(
          text: measure.sanitize(line.text, titleFont),
          left: center - lineWidth / 2,
          top: y,
          fontSize: titleSize,
          font: titleFont,
        ),
      );
      y += titleSize * 1.25;
    }

    final subtitle = book.subtitle;
    if (subtitle != null && subtitle.isNotEmpty) {
      y += subtitleSize * 1.4;
      final subtitleFont = fonts.select(isBold: false, isItalic: true);
      for (final line in measure.wrap(
        subtitle,
        subtitleFont,
        subtitleSize,
        contentWidth * 0.8,
      )) {
        final lineWidth = measure.widthOf(
          line.text,
          subtitleFont,
          subtitleSize,
        );
        texts.add(
          PdfTextRun(
            text: measure.sanitize(line.text, subtitleFont),
            left: center - lineWidth / 2,
            top: y,
            fontSize: subtitleSize,
            font: subtitleFont,
          ),
        );
        y += subtitleSize * 1.35;
      }
    }

    if (book.authors.isNotEmpty) {
      y += authorSize * 2;
      final authorFont = fonts.select(isBold: false, isItalic: false);
      final authors = book.authors.join(', ');
      final lineWidth = measure.widthOf(authors, authorFont, authorSize);
      texts.add(
        PdfTextRun(
          text: measure.sanitize(authors, authorFont),
          left: center - lineWidth / 2,
          top: y,
          fontSize: authorSize,
          font: authorFont,
        ),
      );
    }

    return PdfPageContent(
      pageWidth: geometry.pageWidth,
      pageHeight: geometry.pageHeight,
      isEven: isEven,
      pageNumber: 1,
      texts: texts,
      images: const <PdfImageRun>[],
    );
  }

  List<PdfPageContent> _paginateToc(
    ExportBook book,
    List<int> chapterStarts,
    int frontMatter,
  ) {
    if (!options.includeTableOfContents) {
      return const <PdfPageContent>[];
    }

    final tocWriter = PdfTocWriter(
      geometry: geometry,
      measure: measure,
      fonts: fonts,
      options: options,
    );

    var tocCount = 1;
    var pages = const <PdfPageContent>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      final entries = <PdfTocEntry>[
        for (var index = 0; index < book.chapters.length; index++)
          PdfTocEntry(
            title: book.chapters[index].title,
            pageNumber: frontMatter + tocCount + chapterStarts[index] + 1,
            destination: chapterDestination(index),
          ),
      ];
      pages = tocWriter.layout(entries);
      if (pages.length == tocCount) {
        break;
      }
      tocCount = pages.length;
    }
    return pages;
  }

  void _addChapter(
    PdfPaginationState state,
    ExportChapter chapter,
    int chapterIndex,
  ) {
    final titleStyle = typography.styleFor(ExportBlockType.heading1);
    _addTextBlock(state, chapter.title, titleStyle, chapterIndex);

    for (final block in chapter.blocks) {
      final style = typography.styleFor(block.type);
      switch (block.type) {
        case ExportBlockType.paragraph:
        case ExportBlockType.heading1:
        case ExportBlockType.heading2:
        case ExportBlockType.heading3:
        case ExportBlockType.listItem:
        case ExportBlockType.quote:
        case ExportBlockType.code:
        case ExportBlockType.footnote:
          _addTextBlock(state, block.text, style, chapterIndex);
        case ExportBlockType.image:
          _addImage(state, block, style, chapterIndex);
        case ExportBlockType.pageBreak:
          state.startPage(chapterIndex: chapterIndex);
      }
    }
  }

  void _addTextBlock(
    PdfPaginationState state,
    String text,
    PdfTextStyle style,
    int chapterIndex,
  ) {
    if (text.isEmpty && style.fontSize == 0) {
      return;
    }
    final font = fonts.select(isBold: style.isBold, isItalic: style.isItalic);
    final page = state.current!;
    final availableWidth =
        geometry.contentWidth(page.isEven) -
        style.indentLeft -
        style.indentRight;
    final lines = measure.wrap(
      text,
      font,
      style.fontSize,
      availableWidth,
      hyphenate: options.hyphenation,
    );
    final leading = style.fontSize * style.lineHeight;
    final contentBottom = geometry.contentTop() + geometry.contentHeight();

    var cursor = state.cursor + style.spaceBefore;

    if (style.keepWithNext &&
        cursor + lines.length * leading + leading * 2 > contentBottom) {
      state.startPage(chapterIndex: chapterIndex);
      cursor = state.cursor;
    }

    for (var index = 0; index < lines.length; index++) {
      if (cursor + leading > contentBottom) {
        state.startPage(chapterIndex: chapterIndex);
        cursor = 0;
      }
      final line = lines[index];
      final isLastLine = index == lines.length - 1;
      var wordSpacing = 0.0;
      if (style.isJustified && !isLastLine && line.wordCount > 1) {
        final extra = availableWidth - line.width;
        final spaceWidth = measure.widthOf(' ', font, style.fontSize);
        if (extra > 0 && spaceWidth > 0) {
          wordSpacing = extra / (line.wordCount - 1) / spaceWidth;
        }
      }
      final left =
          geometry.contentLeft(state.current!.isEven) + style.indentLeft;
      state.addText(
        PdfTextRun(
          text: measure.sanitize(line.text, font),
          left: left,
          top: geometry.contentTop() + cursor,
          fontSize: style.fontSize,
          font: font,
          wordSpacing: wordSpacing,
        ),
      );
      cursor += leading;
    }

    state.cursor = cursor + style.spaceAfter;
  }

  void _addImage(
    PdfPaginationState state,
    ExportBlock block,
    PdfTextStyle style,
    int chapterIndex,
  ) {
    final image = block.image;
    if (image == null) {
      return;
    }
    final page = state.current!;
    final maxWidth = geometry.contentWidth(page.isEven);
    final size = ImageSizes.of(image.bytes);
    final dimensions = _imageSize(image, size, maxWidth);
    var cursor = state.cursor + style.spaceBefore;

    if (cursor + dimensions.$2 >
        geometry.contentTop() + geometry.contentHeight()) {
      state.startPage(chapterIndex: chapterIndex);
      cursor = 0;
    }

    state.addImage(
      PdfImageRun(
        bytes: image.bytes,
        left:
            geometry.contentLeft(state.current!.isEven) +
            (maxWidth - dimensions.$1) / 2,
        top: geometry.contentTop() + cursor,
        width: dimensions.$1,
        height: dimensions.$2,
      ),
    );
    state.cursor = cursor + dimensions.$2 + style.spaceAfter;
  }

  (double, double) _imageSize(
    ExportImage image,
    ImageSize? size,
    double maxWidth,
  ) {
    if (size == null) {
      final width = maxWidth * 0.6;
      return (width, width * 0.66);
    }
    final naturalWidth = size.width / options.imageDpi * 72;
    final width = naturalWidth < maxWidth ? naturalWidth : maxWidth;
    final ratio = size.aspectRatio == 0 ? 1.0 : size.aspectRatio;
    return (width, width / ratio);
  }
}

/// Nom de la destination interne d'un chapitre (sommaire cliquable).
String chapterDestination(int index) => 'chapitre-${index + 1}';
