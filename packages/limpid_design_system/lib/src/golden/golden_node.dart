import 'package:flutter/foundation.dart';

/// Un noeud de la description structurelle d'un rendu.
///
/// Le noeud porte le type du widget, le texte qu'il affiche et les faits de
/// style **resolus** : la couleur de fond, le rayon, les espacements, les
/// tailles. Ces faits viennent de l'arbre de rendu, pas de l'arbre de widgets :
/// une couleur declaree par un theme est donc capturee telle qu'elle est
/// peinte.
@immutable
class GoldenNode {
  /// Cree un noeud.
  const GoldenNode({
    required this.type,
    this.text,
    this.facts = const <String, String>{},
    this.children = const <GoldenNode>[],
  });

  /// Le type du widget, sans ses arguments de type.
  final String type;

  /// Le texte affiche par le widget, quand il en porte un.
  final String? text;

  /// Les faits de style resolus, tries par cle a la lecture.
  final Map<String, String> facts;

  /// Les enfants du noeud, dans l'ordre du rendu.
  final List<GoldenNode> children;
}

/// La description structurelle d'un rendu.
///
/// La description se lit comme une arborescence : une ligne par noeud, deux
/// espaces d'indentation par niveau. Elle ne depend ni de la plateforme, ni
/// du moteur de rendu, ni de la police installee : deux machines decrivent le
/// meme rendu de la meme maniere.
@immutable
class GoldenDescription {
  /// Cree une description.
  const GoldenDescription({required this.root});

  /// La racine de la description.
  final GoldenNode root;

  /// Les lignes de la description, une par noeud.
  List<String> toLines() => _linesOf(root, 0);

  /// Les lignes de la description, a partir d'un noeud donne.
  static List<String> _linesOf(GoldenNode node, int depth) {
    final List<String> parts = <String>[node.type];
    final String? text = node.text;
    if (text != null) {
      parts.add('text="${_escape(text)}"');
    }
    final List<String> keys = node.facts.keys.toList(growable: false)..sort();
    for (final String key in keys) {
      parts.add('$key=${_quoteWhenNeeded(node.facts[key]!)}');
    }
    final List<String> lines = <String>["${'  ' * depth}${parts.join(' ')}"];
    for (final GoldenNode child in node.children) {
      lines.addAll(_linesOf(child, depth + 1));
    }
    return lines;
  }

  /// Entoure une valeur de guillemets quand elle contient un espace.
  ///
  /// La ligne du temoin reste ainsi lisible : une valeur.composee se lit
  /// d'un bloc.
  static String _quoteWhenNeeded(String value) =>
      value.contains(' ') ? '"${_escape(value)}"' : value;

  /// Echappe un texte pour qu'il tienne sur une seule ligne.
  static String _escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
}
