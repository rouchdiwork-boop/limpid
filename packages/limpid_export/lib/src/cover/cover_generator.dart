import 'dart:convert';
import 'dart:typed_data';

import '../model/export_book.dart';
import '../model/export_image.dart';
import '../model/export_result.dart';
import '../util/file_name.dart';
import 'cover_image.dart';
import 'cover_svg_writer.dart';
import 'cover_variant.dart';

/// Generates the cover of a book from its metadata.
///
/// The generator never draws: it hands the metadata of the book to the
/// writer of the SVG documents, which produces a vector cover. The result
/// is deterministic: the same book always yields the same bytes.
class CoverGenerator {
  /// Creates a generator.
  const CoverGenerator({this.writer = const CoverSvgWriter()});

  /// The writer of the SVG documents.
  final CoverSvgWriter writer;

  /// Renders the cover of [book] as an SVG document.
  String render(ExportBook book, {CoverVariant variant = CoverVariant.front}) {
    return writer.render(book, variant: variant);
  }

  /// Generates the cover of [book] and returns the produced file.
  Future<ExportResult> generate(
    ExportBook book, {
    CoverVariant variant = CoverVariant.front,
  }) async {
    final svg = render(book, variant: variant);
    return ExportResult(
      bytes: Uint8List.fromList(utf8.encode(svg)),
      fileName: coverFileName(book),
      mimeType: CoverImage.svgMimeType,
    );
  }

  /// Generates the cover of [book] as an image ready to be embedded.
  ///
  /// The image is named the way the HTML writers expect it: the file name
  /// is the path of the image next to the exported document.
  Future<ExportImage> generateImage(
    ExportBook book, {
    CoverVariant variant = CoverVariant.front,
  }) async {
    final svg = render(book, variant: variant);
    return CoverImage(
      bytes: Uint8List.fromList(utf8.encode(svg)),
      altText: 'Couverture de ${book.title}',
      fileName: 'images/${coverFileName(book)}',
    );
  }

  /// Returns a copy of [book] carrying the generated cover.
  ///
  /// The cover the book already carries is kept, unless [replaceExisting]
  /// is true: an uploaded cover always wins over a generated one.
  Future<ExportBook> attach(
    ExportBook book, {
    CoverVariant variant = CoverVariant.front,
    bool replaceExisting = false,
  }) async {
    if (book.coverImage != null && !replaceExisting) {
      return book;
    }
    final image = await generateImage(book, variant: variant);
    return book.copyWith(coverImage: image);
  }

  /// The name of the cover file of a book.
  static String coverFileName(ExportBook book) =>
      '${FileNames.slug(book.title)}-cover.svg';
}

/// Generates the cover of [book] and returns the produced file.
///
/// The shortcut of the [CoverGenerator] for the callers that only need the
/// image.
Future<ExportResult> generateCover(
  ExportBook book, {
  CoverVariant variant = CoverVariant.front,
}) {
  return const CoverGenerator().generate(book, variant: variant);
}
