import 'dart:typed_data';

import 'embedded_font.dart';

/// Charge un asset binaire (typiquement une police).
///
/// L'application Flutter fournit cette fonction via `rootBundle.load` ; le
/// package d'export, being pur Dart, n'a aucun acces direct aux assets.
typedef FontAssetLoader = Future<Uint8List?> Function(String assetPath);

/// Famille de police resolue, avec ses variantes disponibles.
class ResolvedFontFamily {
  /// Cree une famille resolue.
  const ResolvedFontFamily({
    required this.requestedFamily,
    required this.effectiveFamily,
    this.regular,
    this.bold,
    this.italic,
    this.boldItalic,
  });

  /// Famille demandee par l'appelant.
  final String requestedFamily;

  /// Famille reellement utilisee (la demandee, ou une substitution).
  final String effectiveFamily;

  /// Octets de la variante normale.
  final Uint8List? regular;

  /// Octets de la variante grasse.
  final Uint8List? bold;

  /// Octets de la variante italique.
  final Uint8List? italic;

  /// Octets de la variante grasse italique.
  final Uint8List? boldItalic;

  /// Vrai si aucune police embarquee n'a pu etre chargee.
  bool get isFallback => regular == null;

  /// Octets de la variante demandee, avec repli sur la variante normale.
  Uint8List? bytesFor(FontVariant variant) {
    switch (variant) {
      case FontVariant.regular:
        return regular;
      case FontVariant.bold:
        return bold ?? regular;
      case FontVariant.italic:
        return italic ?? regular;
      case FontVariant.boldItalic:
        return boldItalic ?? bold ?? italic ?? regular;
    }
  }
}

/// Registre des polices embarquees.
///
/// Les polices sont chargees a la demande puis mises en cache, afin qu'un
/// export long ne recharge pas les memes octets pour chaque bloc.
class FontRegistry {
  /// Cree un registre.
  ///
  /// [loader] est fourni par l'application ; s'il est absent, aucune police
  /// n'est disponible et les generateurs utilisent leur police de
  /// substitution.
  FontRegistry({this.loader});

  /// Chargeur d'assets fourni par l'application.
  final FontAssetLoader? loader;
  final Map<String, Uint8List> _cache = <String, Uint8List>{};

  /// Charge (et met en cache) les octets d'un asset.
  ///
  /// Renvoie `null` si l'asset est absent ou illisible.
  Future<Uint8List?> load(EmbeddedFont font) async {
    final cached = _cache[font.assetPath];
    if (cached != null) {
      return cached;
    }
    final loader = this.loader;
    if (loader == null) {
      return null;
    }
    try {
      final bytes = await loader(font.assetPath);
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      _cache[font.assetPath] = bytes;
      return bytes;
    } on Object {
      // Un asset illisible ne doit pas interrompre l'export : le generateur
      // basculera sur la police de substitution et signalera l'avertissement.
      return null;
    }
  }

  /// Resout une famille de police.
  ///
  /// Si la famille demandee n'est pas embarquee, la premiere famille du
  /// catalogue disponible est utilisee ; a defaut, la famille est signalee
  /// comme substituee.
  Future<ResolvedFontFamily> resolve(String family) async {
    final candidates = <String>[
      family,
      ...LimpidFonts.families.where((name) => name != family),
    ];
    for (final candidate in candidates) {
      final resolved = await _resolveExact(candidate);
      if (!resolved.isFallback) {
        return ResolvedFontFamily(
          requestedFamily: family,
          effectiveFamily: candidate,
          regular: resolved.regular,
          bold: resolved.bold,
          italic: resolved.italic,
          boldItalic: resolved.boldItalic,
        );
      }
    }
    return ResolvedFontFamily(
      requestedFamily: family,
      effectiveFamily: LimpidFonts.substitutions[family] ?? family,
    );
  }

  Future<ResolvedFontFamily> _resolveExact(String family) async {
    final regular = await load(
      LimpidFonts.assetFor(family, FontVariant.regular),
    );
    final bold = await load(LimpidFonts.assetFor(family, FontVariant.bold));
    final italic = await load(LimpidFonts.assetFor(family, FontVariant.italic));
    final boldItalic = await load(
      LimpidFonts.assetFor(family, FontVariant.boldItalic),
    );
    return ResolvedFontFamily(
      requestedFamily: family,
      effectiveFamily: family,
      regular: regular,
      bold: bold,
      italic: italic,
      boldItalic: boldItalic,
    );
  }
}
