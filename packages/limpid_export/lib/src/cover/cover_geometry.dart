import 'cover_variant.dart';

/// A rectangle of a cover, in the unit of the SVG document.
class CoverRect {
  /// Creates a rectangle.
  const CoverRect(this.x, this.y, this.width, this.height);

  /// A rectangle without surface.
  static const CoverRect empty = CoverRect(0, 0, 0, 0);

  /// The abscissa of the left edge.
  final double x;

  /// The ordinate of the top edge.
  final double y;

  /// The width of the rectangle.
  final double width;

  /// The height of the rectangle.
  final double height;

  /// The abscissa of the right edge.
  double get right => x + width;

  /// The ordinate of the bottom edge.
  double get bottom => y + height;

  @override
  String toString() => 'CoverRect($x, $y, $width, $height)';
}

/// The panels a cover is made of.
class CoverPanels {
  /// Creates a set of panels.
  const CoverPanels({
    required this.foreEdge,
    required this.back,
    required this.spine,
    required this.front,
  });

  /// The narrow strip folded on the fore-edge.
  final CoverRect foreEdge;

  /// The back cover, fold strip included.
  final CoverRect back;

  /// The spine.
  final CoverRect spine;

  /// The front cover.
  final CoverRect front;
}

/// The layout of a cover variant: its canvas and its panels.
class CoverLayout {
  /// Creates a layout.
  const CoverLayout({
    required this.width,
    required this.height,
    required this.panels,
  });

  /// The width of the canvas.
  final double width;

  /// The height of the canvas.
  final double height;

  /// The panels drawn on the canvas.
  final CoverPanels panels;

  @override
  String toString() => 'CoverLayout($width x $height)';
}

/// The geometry of the generated covers.
///
/// The dimensions follow the print model of the mockup: a 6 x 9 inch face at
/// 300 dpi, a 15 mm spine, a 10 mm fold and a 3 mm fore-edge. Every value
/// is expressed in pixels of the SVG document.
///
/// The four variants do not share the same canvas:
///
/// - the front cover is the face of the book;
/// - the back cover is the face plus the strip that folds on the spine;
/// - the spine is the narrow strip between the two faces;
/// - the full wrap lays the fore-edge, the back cover, the spine and the
///   front cover side by side.
class CoverGeometry {
  /// Creates a geometry.
  const CoverGeometry({
    this.faceWidth = 1800,
    this.faceHeight = 2700,
    this.spineWidth = 177,
    this.foldWidth = 118,
    this.foreEdgeWidth = 35,
    this.paddingRatio = 0.13,
  });

  /// The width of a face, in pixels (6 inches at 300 dpi).
  final double faceWidth;

  /// The height of a face, in pixels (9 inches at 300 dpi).
  final double faceHeight;

  /// The width of the spine, in pixels (15 mm at 300 dpi).
  final double spineWidth;

  /// The width of the fold, in pixels (10 mm at 300 dpi).
  final double foldWidth;

  /// The width of the fore-edge, in pixels (3 mm at 300 dpi).
  final double foreEdgeWidth;

  /// The padding inside a panel, against the width of the face.
  final double paddingRatio;

  /// The padding applied inside a panel of the given width.
  double paddingOf(double width) => width * paddingRatio;

  /// The layout of a variant.
  CoverLayout layoutOf(CoverVariant variant) {
    switch (variant) {
      case CoverVariant.front:
        return CoverLayout(
          width: faceWidth,
          height: faceHeight,
          panels: CoverPanels(
            foreEdge: CoverRect.empty,
            back: CoverRect.empty,
            spine: CoverRect.empty,
            front: CoverRect(0, 0, faceWidth, faceHeight),
          ),
        );
      case CoverVariant.back:
        return CoverLayout(
          width: faceWidth + foldWidth,
          height: faceHeight,
          panels: CoverPanels(
            foreEdge: CoverRect.empty,
            back: CoverRect(0, 0, faceWidth + foldWidth, faceHeight),
            spine: CoverRect.empty,
            front: CoverRect.empty,
          ),
        );
      case CoverVariant.spine:
        return CoverLayout(
          width: spineWidth,
          height: faceHeight,
          panels: CoverPanels(
            foreEdge: CoverRect.empty,
            back: CoverRect.empty,
            spine: CoverRect(0, 0, spineWidth, faceHeight),
            front: CoverRect.empty,
          ),
        );
      case CoverVariant.full:
        final backX = foreEdgeWidth;
        final spineX = backX + faceWidth + foldWidth;
        final frontX = spineX + spineWidth;
        return CoverLayout(
          width: frontX + faceWidth,
          height: faceHeight,
          panels: CoverPanels(
            foreEdge: CoverRect(0, 0, foreEdgeWidth, faceHeight),
            back: CoverRect(backX, 0, faceWidth + foldWidth, faceHeight),
            spine: CoverRect(spineX, 0, spineWidth, faceHeight),
            front: CoverRect(frontX, 0, faceWidth, faceHeight),
          ),
        );
    }
  }
}
