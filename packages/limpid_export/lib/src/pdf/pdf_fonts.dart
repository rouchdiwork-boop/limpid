import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../fonts/embedded_font.dart';
import '../fonts/font_registry.dart';

/// Une variante de police, avec son widget de rendu et sa police de mesure.
class PdfFontVariant {
  /// Cree une variante de police.
  const PdfFontVariant({
    required this.widget,
    required this.metric,
    required this.isFallback,
  });

  /// Police utilisee par le widget PDF.
  final pw.Font widget;

  /// Police utilisee pour mesurer le texte.
  final PdfFont metric;

  /// Vrai si la police est une substitution livree avec le moteur PDF.
  final bool isFallback;

  /// Vrai si la police peut rendre le caractere [rune].
  bool supports(int rune) {
    try {
      return metric.isRuneSupported(rune);
    } on Object {
      return false;
    }
  }
}

/// Ensemble des polices utilisees par un export PDF.
class PdfFontSet {
  /// Cree un ensemble de polices.
  const PdfFontSet({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
    required this.familyName,
  });

  /// Variante normale.
  final PdfFontVariant regular;

  /// Variante grasse.
  final PdfFontVariant bold;

  /// Variante italique.
  final PdfFontVariant italic;

  /// Variante grasse italique.
  final PdfFontVariant boldItalic;

  /// Nom de la famille effectivement utilisee.
  final String familyName;

  /// Selectionne la variante correspondant a un style.
  PdfFontVariant select({required bool isBold, required bool isItalic}) {
    if (isBold && isItalic) {
      return boldItalic;
    }
    if (isBold) {
      return bold;
    }
    if (isItalic) {
      return italic;
    }
    return regular;
  }

  /// Vrai si au moins une police de substitution est utilisee.
  bool get hasFallback =>
      regular.isFallback ||
      bold.isFallback ||
      italic.isFallback ||
      boldItalic.isFallback;

  /// Resout les polices d'une famille demandee.
  ///
  /// Si la famille n'est pas embarquee, les polices livrees avec le moteur
  /// PDF (Times, Helvetica, Courier) sont utilisees comme substitution.
  static Future<PdfFontSet> resolve(
    FontRegistry registry,
    String family,
  ) async {
    final resolved = await registry.resolve(family);
    if (resolved.isFallback) {
      return _fallbackSet(family);
    }
    return _embeddedSet(resolved);
  }

  static PdfFontSet _fallbackSet(String family) {
    final document = PdfDocument();
    final substitution = LimpidFonts.substitutions[family] ?? 'Times';
    return PdfFontSet(
      familyName: substitution,
      regular: _fallbackVariant(substitution, 'regular', document),
      bold: _fallbackVariant(substitution, 'bold', document),
      italic: _fallbackVariant(substitution, 'italic', document),
      boldItalic: _fallbackVariant(substitution, 'boldItalic', document),
    );
  }

  static PdfFontVariant _fallbackVariant(
    String substitution,
    String variant,
    PdfDocument document,
  ) {
    final (widget, metric) = switch ((substitution, variant)) {
      ('Helvetica', 'regular') => (
        pw.Font.helvetica(),
        PdfFont.helvetica(document),
      ),
      ('Helvetica', 'bold') => (
        pw.Font.helveticaBold(),
        PdfFont.helveticaBold(document),
      ),
      ('Helvetica', 'italic') => (
        pw.Font.helveticaOblique(),
        PdfFont.helveticaOblique(document),
      ),
      ('Helvetica', 'boldItalic') => (
        pw.Font.helveticaBoldOblique(),
        PdfFont.helveticaBoldOblique(document),
      ),
      ('Courier', 'regular') => (pw.Font.courier(), PdfFont.courier(document)),
      ('Courier', 'bold') => (
        pw.Font.courierBold(),
        PdfFont.courierBold(document),
      ),
      ('Courier', 'italic') => (
        pw.Font.courierOblique(),
        PdfFont.courierOblique(document),
      ),
      ('Courier', 'boldItalic') => (
        pw.Font.courierBoldOblique(),
        PdfFont.courierBoldOblique(document),
      ),
      (_, 'regular') => (pw.Font.times(), PdfFont.times(document)),
      (_, 'bold') => (pw.Font.timesBold(), PdfFont.timesBold(document)),
      (_, 'italic') => (pw.Font.timesItalic(), PdfFont.timesItalic(document)),
      _ => (pw.Font.timesBoldItalic(), PdfFont.timesBoldItalic(document)),
    };
    return PdfFontVariant(widget: widget, metric: metric, isFallback: true);
  }

  static PdfFontSet _embeddedSet(ResolvedFontFamily resolved) {
    final document = PdfDocument();
    PdfFontVariant build(FontVariant variant) {
      final bytes = resolved.bytesFor(variant);
      if (bytes == null) {
        return PdfFontVariant(
          widget: pw.Font.times(),
          metric: PdfFont.times(document),
          isFallback: true,
        );
      }
      final data = _byteData(bytes);
      return PdfFontVariant(
        widget: pw.Font.ttf(data),
        metric: PdfTtfFont(document, data),
        isFallback: false,
      );
    }

    return PdfFontSet(
      familyName: resolved.effectiveFamily,
      regular: build(FontVariant.regular),
      bold: build(FontVariant.bold),
      italic: build(FontVariant.italic),
      boldItalic: build(FontVariant.boldItalic),
    );
  }

  static ByteData _byteData(Uint8List bytes) =>
      bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes);

  /// Message d'avertissement emis lors d'une substitution de police.
  static String fallbackWarning(
    String requestedFamily,
    String effectiveFamily,
  ) {
    return 'Police "$requestedFamily" indisponible : '
        'substitution par "$effectiveFamily".';
  }
}
