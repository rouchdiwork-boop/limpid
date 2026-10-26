import 'dart:convert';
import 'dart:typed_data';

import '../model/export_book.dart';
import '../model/export_format.dart';
import '../model/export_options.dart';
import '../model/export_result.dart';
import 'cover_generator.dart';
import 'cover_variant.dart';

/// Exports a book with a generated cover.
///
/// The exporter attaches the generated cover to the book before handing it
/// over to the writer: the formats that embed a cover (EPUB, ODT) carry the
/// image, the formats that reference a cover (HTML) point at it.
///
/// ```dart
/// final exporter = CoveredExporter(export: const LimpidExporter().export);
/// final result = await exporter(ExportFormat.epub3, book, options);
/// ```
class CoveredExporter {
  /// Creates an exporter.
  const CoveredExporter({
    required this.export,
    this.variant = CoverVariant.front,
    this.generator = const CoverGenerator(),
  });

  /// The writer the covered book is handed over to.
  final Future<ExportResult> Function(
    ExportFormat format,
    ExportBook book,
    ExportOptions options,
  )
  export;

  /// The variant of the cover to generate.
  final CoverVariant variant;

  /// The generator of the cover.
  final CoverGenerator generator;

  /// Exports [book] with a generated cover.
  Future<ExportResult> call(
    ExportFormat format,
    ExportBook book,
    ExportOptions options,
  ) async {
    final covered = await generator.attach(book, variant: variant);
    final result = await export(format, covered, options);
    return _withCoverReference(format, result, covered);
  }

  /// Adds the reference to the cover to the formats that only point at it.
  ///
  /// The EPUB, the ODT and the HTML carry the image or name it themselves;
  /// the Markdown document only needs the reference, printed under the
  /// front matter.
  ExportResult _withCoverReference(
    ExportFormat format,
    ExportResult result,
    ExportBook book,
  ) {
    if (format != ExportFormat.markdown) {
      return result;
    }
    final cover = book.coverImage;
    final path = cover?.fileName;
    if (path == null || path.isEmpty) {
      return result;
    }
    final markdown = utf8.decode(result.bytes);
    final reference = '![Couverture de ${book.title}]($path)\n\n';
    final start = _frontMatterEnd(markdown);
    final updated =
        '${markdown.substring(0, start)}$reference${markdown.substring(start)}';
    return ExportResult(
      bytes: Uint8List.fromList(utf8.encode(updated)),
      fileName: result.fileName,
      mimeType: result.mimeType,
      warnings: result.warnings,
    );
  }

  /// The end of the front matter of a Markdown document.
  static int _frontMatterEnd(String markdown) {
    final match = RegExp(
      r'^---\n.*?\n---\n\n',
      dotAll: true,
    ).firstMatch(markdown);
    return match?.end ?? 0;
  }
}
