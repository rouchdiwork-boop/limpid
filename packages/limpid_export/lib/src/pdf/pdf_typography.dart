import '../model/export_block.dart';
import '../model/export_options.dart';

/// Style typographique d'un bloc dans le PDF.
class PdfTextStyle {
  /// Cree un style typographique.
  const PdfTextStyle({
    required this.fontSize,
    required this.spaceBefore,
    required this.spaceAfter,
    required this.lineHeight,
    this.isBold = false,
    this.isItalic = false,
    this.isMonospace = false,
    this.indentLeft = 0,
    this.indentRight = 0,
    this.isJustified = false,
    this.keepWithNext = false,
  });

  /// Taille de police, en points.
  final double fontSize;

  /// Espace avant le bloc, en points.
  final double spaceBefore;

  /// Espace apres le bloc, en points.
  final double spaceAfter;

  /// Interligne, en multiple de la taille de police.
  final double lineHeight;

  /// Vrai si le texte est en gras.
  final bool isBold;

  /// Vrai si le texte est en italique.
  final bool isItalic;

  /// Vrai si le texte utilise la police a chasse fixe.
  final bool isMonospace;

  /// Retrait gauche, en points.
  final double indentLeft;

  /// Retrait droit, en points.
  final double indentRight;

  /// Vrai si le texte doit etre justifie.
  final bool isJustified;

  /// Vrai si le bloc doit rester avec le bloc suivant.
  final bool keepWithNext;
}

/// Typographie du PDF, derivee des options d'export.
class PdfTypography {
  /// Cree une typographie.
  const PdfTypography(this.options);

  /// Options d'export.
  final ExportOptions options;

  /// Taille du corps de texte, en points.
  double get bodySize => options.fontSize;

  /// Style d'un bloc donne.
  PdfTextStyle styleFor(ExportBlockType type) {
    switch (type) {
      case ExportBlockType.paragraph:
        return PdfTextStyle(
          fontSize: bodySize,
          spaceBefore: 0,
          spaceAfter: bodySize * 0.55,
          lineHeight: options.lineHeight,
          isJustified: options.justifyText,
        );
      case ExportBlockType.heading1:
        return PdfTextStyle(
          fontSize: bodySize * 1.55,
          spaceBefore: bodySize * 1.1,
          spaceAfter: bodySize * 0.7,
          lineHeight: 1.2,
          isBold: true,
          keepWithNext: true,
        );
      case ExportBlockType.heading2:
        return PdfTextStyle(
          fontSize: bodySize * 1.25,
          spaceBefore: bodySize * 0.9,
          spaceAfter: bodySize * 0.5,
          lineHeight: 1.25,
          isBold: true,
          keepWithNext: true,
        );
      case ExportBlockType.heading3:
        return PdfTextStyle(
          fontSize: bodySize * 1.08,
          spaceBefore: bodySize * 0.8,
          spaceAfter: bodySize * 0.4,
          lineHeight: 1.3,
          isBold: true,
          isItalic: true,
          keepWithNext: true,
        );
      case ExportBlockType.listItem:
        return PdfTextStyle(
          fontSize: bodySize,
          spaceBefore: 0,
          spaceAfter: bodySize * 0.3,
          lineHeight: options.lineHeight,
          indentLeft: bodySize * 1.2,
        );
      case ExportBlockType.quote:
        return PdfTextStyle(
          fontSize: bodySize * 0.95,
          spaceBefore: bodySize * 0.6,
          spaceAfter: bodySize * 0.6,
          lineHeight: options.lineHeight,
          isItalic: true,
          indentLeft: bodySize * 1.2,
          indentRight: bodySize * 0.8,
        );
      case ExportBlockType.code:
        return PdfTextStyle(
          fontSize: bodySize * 0.85,
          spaceBefore: bodySize * 0.5,
          spaceAfter: bodySize * 0.5,
          lineHeight: 1.35,
          isMonospace: true,
          indentLeft: bodySize * 0.6,
        );
      case ExportBlockType.image:
        return PdfTextStyle(
          fontSize: bodySize,
          spaceBefore: bodySize * 0.6,
          spaceAfter: bodySize * 0.6,
          lineHeight: 1,
        );
      case ExportBlockType.pageBreak:
        return const PdfTextStyle(
          fontSize: 0,
          spaceBefore: 0,
          spaceAfter: 0,
          lineHeight: 0,
        );
      case ExportBlockType.footnote:
        return PdfTextStyle(
          fontSize: bodySize * 0.8,
          spaceBefore: bodySize * 0.3,
          spaceAfter: bodySize * 0.3,
          lineHeight: 1.3,
        );
    }
  }
}
