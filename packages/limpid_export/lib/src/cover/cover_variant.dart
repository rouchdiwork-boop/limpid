/// The part of a book cover an image represents.
///
/// The enumeration mirrors `CoverVariant` of `limpid_core`: the export
/// package stays independent from the domain package, so the application
/// maps the two values one to one.
///
/// The four variants follow the print model of the mockup:
///
/// - [front]: the front cover, the face of the book;
/// - [back]: the back cover, with the strip that folds on the spine;
/// - [full]: the whole wrap, fore-edge, back cover, spine and front cover;
/// - [spine]: the spine only.
enum CoverVariant {
  /// The front cover only.
  front,

  /// The back cover only, fold strip included.
  back,

  /// The whole wrap: fore-edge, back cover, spine and front cover.
  full,

  /// The spine only.
  spine;

  /// The variant named [name], `null` when the name is unknown.
  ///
  /// The name is the technical name of the variant (`front`, `back`,
  /// `full`, `spine`), case and spaces ignored: a route that lets the
  /// caller choose reads the choice with this method.
  static CoverVariant? tryParse(String name) {
    final String normalized = name.trim().toLowerCase();
    for (final CoverVariant variant in CoverVariant.values) {
      if (variant.name == normalized) return variant;
    }
    return null;
  }
}
