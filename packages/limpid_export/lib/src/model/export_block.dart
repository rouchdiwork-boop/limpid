import 'export_block_type.dart';
import 'export_image.dart';

export 'export_block_type.dart';

/// Bloc de contenu atomique du modele intermediaire d'export.
///
/// Un bloc est l'unite de contenu manipulee par les generateurs. Il ne
/// contient pas de mise en forme enrichie : seuls le [type], le [text] et
/// quelques metadonnees structurelles sont transportes, afin que chaque
/// format cible puisse appliquer sa propre typographie.
class ExportBlock {
  /// Cree un bloc de contenu.
  const ExportBlock({
    required this.type,
    required this.text,
    this.href,
    this.level,
    this.footnotes = const <String>[],
    this.image,
    this.language,
  });

  /// Bloc de paragraphe simple.
  const ExportBlock.paragraph(
    String text, {
    List<String> footnotes = const <String>[],
  }) : this(type: ExportBlockType.paragraph, text: text, footnotes: footnotes);

  /// Bloc de titre de niveau 1.
  const ExportBlock.heading1(String text)
    : this(type: ExportBlockType.heading1, text: text);

  /// Bloc de titre de niveau 2.
  const ExportBlock.heading2(String text)
    : this(type: ExportBlockType.heading2, text: text);

  /// Bloc de titre de niveau 3.
  const ExportBlock.heading3(String text)
    : this(type: ExportBlockType.heading3, text: text);

  /// Bloc de citation.
  const ExportBlock.quote(String text)
    : this(type: ExportBlockType.quote, text: text);

  /// Bloc de code.
  const ExportBlock.code(String text, {String? language})
    : this(type: ExportBlockType.code, text: text, language: language);

  /// Bloc de liste.
  const ExportBlock.listItem(String text, {int? level})
    : this(type: ExportBlockType.listItem, text: text, level: level);

  /// Bloc d'illustration.
  const ExportBlock.image(ExportImage image, {String? altText, String? href})
    : this(
        type: ExportBlockType.image,
        text: altText ?? '',
        href: href,
        image: image,
      );

  /// Bloc de saut de page explicite.
  const ExportBlock.pageBreak()
    : this(type: ExportBlockType.pageBreak, text: '');

  /// Bloc de note de bas de page autonome.
  const ExportBlock.footnote(String text)
    : this(type: ExportBlockType.footnote, text: text);

  /// Nature du bloc.
  final ExportBlockType type;

  /// Texte du bloc (vide pour les blocs sans contenu textuel).
  final String text;

  /// Cible associee : URL d'un lien, source d'une illustration, ancre.
  final String? href;

  /// Niveau de profondeur : niveau de titre, indentation de liste.
  final int? level;

  /// Notes de bas de page rattachees a ce bloc.
  ///
  /// Les notes sont numerotees automatiquement, par chapitre, dans l'ordre
  /// d'apparition.
  final List<String> footnotes;

  /// Illustrationtransportee par le bloc (type [ExportBlockType.image]).
  final ExportImage? image;

  /// Langue du bloc, pour la typographie (balise `lang` en HTML/EPUB).
  final String? language;

  /// Copie immuable du bloc avec des champs remplaces.
  ExportBlock copyWith({
    ExportBlockType? type,
    String? text,
    String? href,
    int? level,
    List<String>? footnotes,
    ExportImage? image,
    String? language,
  }) {
    return ExportBlock(
      type: type ?? this.type,
      text: text ?? this.text,
      href: href ?? this.href,
      level: level ?? this.level,
      footnotes: footnotes ?? this.footnotes,
      image: image ?? this.image,
      language: language ?? this.language,
    );
  }

  @override
  String toString() => 'ExportBlock(${type.name}, ${text.length} car.)';
}
