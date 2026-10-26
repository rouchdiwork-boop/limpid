/// Echappement HTML.
///
/// Utilise pour tout texte provenant du livre : le contenu d'un auteur ne
/// doit jamais pouvoir injecter de balise.
class HtmlEscape {
  const HtmlEscape._();

  /// Echappe un texte destined au corps du document.
  static String text(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// Echappe une valeur destinee a un attribut entre guillemets.
  static String attribute(String value) {
    return text(value).replaceAll('"', '&quot;').replaceAll("'", '&#39;');
  }
}
