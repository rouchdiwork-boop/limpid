import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../fonts/embedded_font.dart';
import '../fonts/font_registry.dart';

/// Les polices de la couverture, resolues pour le rendu SVG.
///
/// La couverture generee emploie deux familles : une serif de titre et une
/// serif de manuscrit. Le moteur PDF les resout dans le registre des
/// polices embarquees ; a defaut de police embarquee, les polices livrees
/// avec le moteur PDF sont utilisees.
class PdfCoverFonts {
  /// Cree un ensemble de polices de couverture.
  const PdfCoverFonts({
    required this.titleRegular,
    required this.titleBold,
    required this.bodyRegular,
    required this.bodyBold,
  });

  /// La variante normale de la police de titre.
  final pw.Font titleRegular;

  /// La variante grasse de la police de titre.
  final pw.Font titleBold;

  /// La variante normale de la police de manuscrit.
  final pw.Font bodyRegular;

  /// La variante grasse de la police de manuscrit.
  final pw.Font bodyBold;

  /// La famille de titre de la couverture.
  static const String titleFamily = 'Fraunces';

  /// La famille de manuscrit de la couverture.
  static const String bodyFamily = 'Literata';

  /// Resout les polices de la couverture dans le registre.
  static Future<PdfCoverFonts> resolve(FontRegistry registry) async {
    final title = await registry.resolve(titleFamily);
    final body = await registry.resolve(bodyFamily);
    return PdfCoverFonts(
      titleRegular: _fontOf(title.bytesFor(FontVariant.regular)),
      titleBold: _fontOf(title.bytesFor(FontVariant.bold)),
      bodyRegular: _fontOf(body.bytesFor(FontVariant.regular)),
      bodyBold: _fontOf(body.bytesFor(FontVariant.bold)),
    );
  }

  /// La police a employer pour un style SVG.
  ///
  /// [fontFamily] reçoit la pile de polices declaree par le document SVG.
  /// Renvoie `null` quand la famille n'est pas connue : le moteur PDF
  /// utilise alors sa propre police de substitution.
  pw.Font? lookup(String fontFamily, String fontStyle, String fontWeight) {
    final isBold = _isBold(fontWeight);
    if (fontFamily.contains(titleFamily)) {
      return isBold ? titleBold : titleRegular;
    }
    if (fontFamily.contains(bodyFamily)) {
      return isBold ? bodyBold : bodyRegular;
    }
    return null;
  }

  static pw.Font _fontOf(Uint8List? bytes) {
    if (bytes == null) {
      return pw.Font.times();
    }
    return pw.Font.ttf(
      bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }

  static bool _isBold(String weight) {
    final normalized = weight.trim().toLowerCase();
    if (normalized == 'bold' || normalized == 'bolder') {
      return true;
    }
    final value = int.tryParse(normalized);
    return value != null && value >= 600;
  }
}
