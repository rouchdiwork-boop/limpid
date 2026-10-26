import 'package:xml/xml.dart';

/// Fabrique de documents XML.
///
/// Encapsule la declaration XML et le DOCTYPE eventuel, et garantit un
/// echappement systematique du contenu textuel.
class XmlWriter {
  XmlWriter._(this._builder);

  final XmlBuilder _builder;

  /// DOCTYPE optionnel du document.
  String? _doctype;

  /// Cree un redacteur XML.
  ///
  /// [doctype] est insere apres la declaration XML (par exemple `html` pour
  /// un document XHTML).
  factory XmlWriter({String? doctype}) {
    final writer = XmlWriter._(XmlBuilder());
    writer._doctype = doctype;
    return writer;
  }

  static const String _declaration = '<?xml version="1.0" encoding="UTF-8"?>';

  /// Ajoute un element.
  ///
  /// [attributes] est ecrit dans l'ordre d'insertion. [nest] permet
  /// d'imbriquer des elements.
  void element(
    String name, {
    Map<String, String> attributes = const <String, String>{},
    void Function()? nest,
  }) {
    _builder.element(name, attributes: attributes, nest: nest);
  }

  /// Ajoute un element avec des namespaces prefixes.
  ///
  /// [namespaces] associe un prefixe a son URI ; la cle `null` declare un
  /// namespace par defaut. Les namespaces declares sur un element ancetre
  /// restent visibles : les elements enfants peuvent utiliser leurs prefixes
  /// sans les redeclarer.
  void namespacedElement(
    String name, {
    Map<String?, String> namespaces = const <String?, String>{},
    Map<String, String> attributes = const <String, String>{},
    void Function()? nest,
  }) {
    _builder.element(
      name,
      namespaceUris: namespaces,
      attributes: attributes,
      nest: nest,
    );
  }

  /// Ajoute du texte (echappe automatiquement).
  void text(String value) => _builder.text(value);

  /// Serialise le document.
  String toXmlString() {
    final body = _builder.buildDocument().toXmlString();
    final doctype = _doctype;
    if (doctype == null) {
      return '$_declaration\n$body';
    }
    return '$_declaration\n<!DOCTYPE $doctype>\n$body';
  }
}
