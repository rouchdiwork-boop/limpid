import '../model/export_book.dart';
import '../util/xml_writer.dart';
import 'cover_geometry.dart';
import 'cover_palette.dart';
import 'cover_svg_format.dart';
import 'cover_text_metrics.dart';
import 'cover_typography.dart';

/// Draws the panels of a cover: front cover, back cover and spine.
///
/// The panels share the same grid as the application: the title is anchored
/// at the top of the face, the author at the bottom, the margin is a
/// fraction of the width of the face.
class CoverSvgPanels {
  const CoverSvgPanels();

  /// Draws the front cover of the book.
  void writeFront(
    XmlWriter writer,
    ExportBook book,
    CoverPalette colors,
    CoverRect rect,
    CoverGeometry geometry,
  ) {
    final padding = geometry.paddingOf(geometry.faceWidth);
    final left = rect.x + padding;
    final contentWidth = rect.width - 2 * padding;
    final titleSize = CoverTypography.titleSize(geometry.faceWidth);
    final titleLines = CoverTextMetrics.fit(
      book.title,
      fontSize: titleSize,
      minFontSize: CoverTypography.minTitleSize(geometry.faceWidth),
      maxWidth: contentWidth,
      maxLines: CoverTypography.maxTitleLines,
    );

    var top = rect.y + padding;
    final subtitle = book.subtitle;
    if (subtitle != null && subtitle.isNotEmpty) {
      final labelSize = CoverTypography.labelSize(geometry.faceWidth);
      final tracking = labelSize * CoverTypography.labelLetterSpacingRatio;
      final label = CoverTextMetrics.truncate(
        subtitle.toUpperCase(),
        fontSize: labelSize,
        maxWidth: contentWidth,
        letterSpacing: tracking,
      );
      writeText(
        writer,
        lines: <String>[label],
        x: left,
        baseline: top + labelSize,
        fontSize: labelSize,
        lineHeight: 1,
        family: CoverTypography.authorStack,
        weight: '500',
        fill: colors.ink,
        opacity: 0.78,
        letterSpacing: tracking,
      );
      top += labelSize + titleSize * 0.45;
    }

    writeText(
      writer,
      lines: titleLines,
      x: left,
      baseline: top + titleSize * 0.8,
      fontSize: titleSize,
      lineHeight: CoverTypography.titleLineHeight,
      family: CoverTypography.titleStack,
      weight: '600',
      fill: colors.ink,
    );

    final authorSize = CoverTypography.authorSize(geometry.faceWidth);
    final author = authorOf(book);
    if (author.isNotEmpty) {
      final tracking = authorSize * CoverTypography.authorLetterSpacingRatio;
      final line = CoverTextMetrics.truncate(
        author.toUpperCase(),
        fontSize: authorSize,
        maxWidth: contentWidth,
        letterSpacing: tracking,
      );
      writeText(
        writer,
        lines: <String>[line],
        x: left,
        baseline: rect.bottom - padding - authorSize * 0.3,
        fontSize: authorSize,
        lineHeight: 1,
        family: CoverTypography.authorStack,
        weight: '500',
        fill: colors.ink,
        opacity: 0.85,
        letterSpacing: tracking,
      );
    }
  }

  /// Draws the back cover of the book.
  ///
  /// The back cover carries the summary of the book, the author and the
  /// imprint; the fold strip on its right is left blank.
  void writeBack(
    XmlWriter writer,
    ExportBook book,
    CoverPalette colors,
    CoverRect rect,
    CoverGeometry geometry,
  ) {
    final padding = geometry.paddingOf(geometry.faceWidth);
    final left = rect.x + padding;
    final contentWidth = rect.width - geometry.foldWidth - 2 * padding;
    if (contentWidth <= 0) {
      return;
    }

    final titleSize = CoverTypography.summarySize(geometry.faceWidth) * 1.5;
    final titleLines = CoverTextMetrics.fit(
      book.title,
      fontSize: titleSize,
      minFontSize: titleSize * 0.7,
      maxWidth: contentWidth,
      maxLines: 2,
    );
    var top = rect.y + padding;
    writeText(
      writer,
      lines: titleLines,
      x: left,
      baseline: top + titleSize * 0.8,
      fontSize: titleSize,
      lineHeight: CoverTypography.titleLineHeight,
      family: CoverTypography.titleStack,
      weight: '600',
      fill: colors.ink,
      opacity: 0.92,
    );
    top += titleSize * 1.2 + titleSize * (titleLines.length - 1);

    writer.element(
      'rect',
      attributes: <String, String>{
        'x': CoverSvgFormat.number(left),
        'y': CoverSvgFormat.number(top),
        'width': CoverSvgFormat.number(contentWidth * 0.22),
        'height': '3',
        'fill': colors.ink,
        'opacity': '0.55',
      },
    );
    top += geometry.faceWidth * 0.035;

    final description = book.metadata.description;
    if (description != null && description.isNotEmpty) {
      final summarySize = CoverTypography.summarySize(geometry.faceWidth);
      final summaryLines = CoverTextMetrics.fit(
        description,
        fontSize: summarySize,
        minFontSize: summarySize * 0.75,
        maxWidth: contentWidth,
        maxLines: 12,
      );
      writeText(
        writer,
        lines: summaryLines,
        x: left,
        baseline: top + summarySize,
        fontSize: summarySize,
        lineHeight: CoverTypography.summaryLineHeight,
        family: CoverTypography.authorStack,
        weight: '400',
        fill: colors.ink,
        opacity: 0.82,
      );
    }

    final authorSize = CoverTypography.authorSize(geometry.faceWidth) * 0.72;
    final author = authorOf(book);
    if (author.isNotEmpty) {
      final tracking = authorSize * CoverTypography.authorLetterSpacingRatio;
      final line = CoverTextMetrics.truncate(
        author.toUpperCase(),
        fontSize: authorSize,
        maxWidth: contentWidth,
        letterSpacing: tracking,
      );
      writeText(
        writer,
        lines: <String>[line],
        x: left,
        baseline: rect.bottom - padding - authorSize * 1.9,
        fontSize: authorSize,
        lineHeight: 1,
        family: CoverTypography.authorStack,
        weight: '500',
        fill: colors.ink,
        opacity: 0.85,
        letterSpacing: tracking,
      );
    }

    final publisher = book.metadata.publisher;
    if (publisher != null && publisher.isNotEmpty) {
      final imprintSize = CoverTypography.summarySize(geometry.faceWidth);
      final imprint = CoverTextMetrics.truncate(
        publisher,
        fontSize: imprintSize,
        maxWidth: contentWidth,
      );
      writeText(
        writer,
        lines: <String>[imprint],
        x: left,
        baseline: rect.bottom - padding - imprintSize * 0.4,
        fontSize: imprintSize,
        lineHeight: 1,
        family: CoverTypography.authorStack,
        weight: '400',
        fill: colors.ink,
        opacity: 0.7,
      );
    }
  }

  /// Draws the spine of the book.
  ///
  /// The text of the spine runs from the bottom to the top, as on a printed
  /// book.
  void writeSpine(
    XmlWriter writer,
    ExportBook book,
    CoverPalette colors,
    CoverRect rect,
    CoverGeometry geometry,
  ) {
    final padding = geometry.paddingOf(geometry.faceWidth);
    final centerX = rect.x + rect.width / 2;
    final centerY = rect.y + rect.height / 2;
    final available = rect.height - 2 * padding;

    final titleSize = CoverTypography.spineTitleSize(geometry.faceWidth);
    final title = CoverTextMetrics.truncate(
      book.title,
      fontSize: titleSize,
      maxWidth: available,
    );
    if (title.isNotEmpty) {
      final titleWidth = CoverTextMetrics.widthOf(title, fontSize: titleSize);
      writer.element(
        'g',
        attributes: <String, String>{
          'transform': 'rotate(-90 $centerX $centerY)',
        },
        nest: () {
          writeText(
            writer,
            lines: <String>[title],
            x: centerX - titleWidth / 2,
            baseline: centerY + titleSize * 0.35,
            fontSize: titleSize,
            lineHeight: 1,
            family: CoverTypography.titleStack,
            weight: '600',
            fill: colors.ink,
          );
        },
      );
    }

    final authorSize = CoverTypography.spineAuthorSize(geometry.faceWidth);
    final author = authorOf(book);
    if (author.isNotEmpty) {
      final tracking = authorSize * CoverTypography.authorLetterSpacingRatio;
      final line = CoverTextMetrics.truncate(
        author.toUpperCase(),
        fontSize: authorSize,
        maxWidth: available,
        letterSpacing: tracking,
      );
      writer.element(
        'g',
        attributes: <String, String>{
          'transform': 'rotate(-90 $centerX $centerY)',
        },
        nest: () {
          writeText(
            writer,
            lines: <String>[line],
            x: centerX - (rect.height / 2 - padding),
            baseline: centerY + authorSize * 0.35,
            fontSize: authorSize,
            lineHeight: 1,
            family: CoverTypography.authorStack,
            weight: '500',
            fill: colors.ink,
            opacity: 0.85,
            letterSpacing: tracking,
          );
        },
      );
    }
  }

  /// Writes a block of text, one line per entry.
  void writeText(
    XmlWriter writer, {
    required List<String> lines,
    required double x,
    required double baseline,
    required double fontSize,
    required double lineHeight,
    required String family,
    required String weight,
    required String fill,
    double opacity = 1,
    double letterSpacing = 0,
  }) {
    if (lines.isEmpty) {
      return;
    }
    final attributes = <String, String>{
      'font-family': family,
      'font-size': CoverSvgFormat.number(fontSize),
      'font-weight': weight,
      'fill': fill,
      'opacity': CoverSvgFormat.number(opacity),
    };
    if (letterSpacing > 0) {
      attributes['letter-spacing'] = CoverSvgFormat.number(letterSpacing);
    }
    writer.element(
      'text',
      attributes: attributes,
      nest: () {
        for (var index = 0; index < lines.length; index++) {
          writer.element(
            'tspan',
            attributes: <String, String>{
              'x': CoverSvgFormat.number(x),
              'y': CoverSvgFormat.number(
                baseline + index * fontSize * lineHeight,
              ),
            },
            nest: () => writer.text(lines[index]),
          );
        }
      },
    );
  }

  /// The authors of the book, as they are printed on the cover.
  static String authorOf(ExportBook book) => book.authors.join(', ');
}
