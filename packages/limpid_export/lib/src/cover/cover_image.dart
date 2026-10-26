import '../model/export_image.dart';

/// An image produced by the cover generator.
///
/// The generator produces SVG documents: their media type is
/// `image/svg+xml`, but the archives of the package expect the `svg`
/// extension. The class therefore carries the media type of a vector image
/// and the extension of an SVG file.
class CoverImage extends ExportImage {
  /// Creates an image from the bytes of an SVG document.
  const CoverImage({required super.bytes, super.altText, super.fileName})
    : super(mimeType: svgMimeType);

  /// The media type of the generated images.
  static const String svgMimeType = 'image/svg+xml';

  @override
  String get extension => 'svg';
}
