import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:limpid_design_system/src/golden/golden_node.dart';

/// Extrait la description structurelle d'un rendu.
///
/// L'extracteur parcourt l'**arbre de rendu** de l'element donne : il lit
/// le type de chaque widget, le texte qu'il porte et les faits de style
/// resolus — la couleur reellement peinte, le rayon reellement applique, les
/// espacements reellement poses.
///
/// Seuls des faits **declares** sont captes : aucune mesure de texte, aucune
/// position absolue, aucun resultat de rendu. La description est donc la
/// meme sur toutes les plateformes, et elle change des que le design
/// systeme change.
abstract final class GoldenExtractor {
  /// Les widgets dont le type porte, a lui seul, une information.
  ///
  /// Un widget de structure — une rangee, une colonne, une icone — se lit
  /// dans l'arbre ; un widget de tuyauterie ne se lit pas.
  static const Set<String> _visibleTypes = <String>{
    'CircularProgressIndicator',
    'Column',
    'CustomPaint',
    'Expanded',
    'Flexible',
    'Icon',
    'Image',
    'LinearProgressIndicator',
    'Positioned',
    'Row',
    'Stack',
    'Wrap',
  };

  /// Decrit l'element et toute sa descendance.
  ///
  /// La description ne garde que les noeuds qui portent une information :
  /// le texte, un fait de style, un widget du design system. Les autres sont
  /// **transparents** — leurs enfants remontent d'un niveau — et la
  /// description reste courte et lisible.
  static GoldenDescription describe(Element element) {
    return GoldenDescription(
      root: GoldenNode(
        type: _typeOf(element.widget.runtimeType),
        text: _textOf(element.widget),
        facts: _factsOf(element),
        children: _childrenOf(element),
      ),
    );
  }

  /// Les enfants visibles d'un element.
  static List<GoldenNode> _childrenOf(Element element) {
    final List<GoldenNode> children = <GoldenNode>[];
    element.visitChildren((Element child) {
      children.addAll(_visibleNodesOf(child));
    });
    return List<GoldenNode>.unmodifiable(children);
  }

  /// Les noeuds visibles d'un element : l'element lui-meme quand il porte
  /// une information, ses enfants sinon.
  static List<GoldenNode> _visibleNodesOf(Element element) {
    final GoldenNode node = _nodeOf(element);
    if (_isVisible(node)) {
      return <GoldenNode>[node];
    }
    // Le noeud est transparent : ses enfants remontent d'un niveau.
    return node.children;
  }

  /// Le noeud d'un element, avec ses enfants visibles.
  static GoldenNode _nodeOf(Element element) {
    return GoldenNode(
      type: _typeOf(element.widget.runtimeType),
      text: _textOf(element.widget),
      facts: _factsOf(element),
      children: _childrenOf(element),
    );
  }

  /// Le noeud porte-t-il une information ?
  static bool _isVisible(GoldenNode node) {
    return node.text != null ||
        node.facts.isNotEmpty ||
        node.type.startsWith('Limpid') ||
        _visibleTypes.contains(node.type);
  }

  /// Le nom du type du widget, sans ses arguments de type.
  static String _typeOf(Type type) {
    final String name = type.toString();
    final int bracket = name.indexOf('<');
    return bracket == -1 ? name : name.substring(0, bracket);
  }

  /// Le texte affiche par le widget, quand il en porte un.
  static String? _textOf(Widget widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    return null;
  }

  /// Les faits de style de l'element.
  static Map<String, String> _factsOf(Element element) {
    final Map<String, String> facts = <String, String>{};
    final Widget widget = element.widget;
    if (widget is Semantics) {
      final String? label = widget.properties.label;
      if (label != null) {
        facts['semanticsLabel'] = label;
      }
      final String? value = widget.properties.value;
      if (value != null) {
        facts['semanticsValue'] = value;
      }
    }
    if (widget is Material && widget.shape != null) {
      facts['shape'] = _shapeName(widget.shape!);
      final String radius = _shapeRadiusFacts(widget.shape!);
      if (radius.isNotEmpty) {
        facts['radius'] = radius;
      }
    }
    // `ComponentElement.renderObject` renvoie le rendu du **premier
    // descendant** : il ne faut pas l'attribuer au widget. Seul un
    // `RenderObjectElement` porte le rendu de son propre widget.
    final RenderObject? render = element is RenderObjectElement
        ? element.renderObject
        : null;
    if (render != null) {
      _renderFacts(render, facts);
    }
    return Map<String, String>.unmodifiable(facts);
  }

  /// Les faits de style tires de l'objet de rendu.
  static void _renderFacts(RenderObject render, Map<String, String> facts) {
    if (render is RenderDecoratedBox) {
      _decorationFacts(render.decoration, facts);
    }
    if (render is RenderPadding) {
      final EdgeInsets padding = render.padding.resolve(render.textDirection);
      facts['padding'] =
          '${_number(padding.left)},${_number(padding.top)},'
          '${_number(padding.right)},${_number(padding.bottom)}';
    }
    if (render is RenderConstrainedBox) {
      _constraintsFacts(render.additionalConstraints, facts);
    }
    if (render is RenderFlex) {
      facts['direction'] = render.direction == Axis.horizontal
          ? 'horizontal'
          : 'vertical';
      if (render.spacing != 0) {
        facts['spacing'] = _number(render.spacing);
      }
    }
    if (render is RenderPhysicalModel) {
      facts['surface'] = _color(render.color);
      if (render.elevation != 0) {
        facts['elevation'] = _number(render.elevation);
      }
    }
    if (render is RenderOpacity) {
      facts['opacity'] = _number(render.opacity);
    }
    if (render is RenderParagraph && render.hasSize) {
      _paragraphFacts(render, facts);
    }
  }

  /// Les faits de la decoration d'une boite.
  static void _decorationFacts(
    Decoration decoration,
    Map<String, String> facts,
  ) {
    if (decoration is BoxDecoration) {
      final Color? color = decoration.color;
      if (color != null) {
        facts['background'] = _color(color);
      }
      final BorderRadiusGeometry? radius = decoration.borderRadius;
      if (radius is BorderRadius) {
        facts['radius'] = _radiusFacts(radius);
      }
      final BoxBorder? border = decoration.border;
      if (border != null) {
        facts['border'] = _borderFacts(border);
      }
      if (decoration.shape != BoxShape.rectangle) {
        facts['shape'] = decoration.shape.name;
      }
      return;
    }
    if (decoration is ShapeDecoration) {
      final Color? color = decoration.color;
      if (color != null) {
        facts['background'] = _color(color);
      }
    }
  }

  /// Les faits des contraintes posees sur une boite.
  static void _constraintsFacts(
    BoxConstraints constraints,
    Map<String, String> facts,
  ) {
    if (constraints.minWidth.isFinite && constraints.minWidth != 0) {
      facts['minWidth'] = _number(constraints.minWidth);
    }
    if (constraints.minHeight.isFinite && constraints.minHeight != 0) {
      facts['minHeight'] = _number(constraints.minHeight);
    }
    if (constraints.maxWidth.isFinite) {
      facts['maxWidth'] = _number(constraints.maxWidth);
    }
    if (constraints.maxHeight.isFinite) {
      facts['maxHeight'] = _number(constraints.maxHeight);
    }
  }

  /// Les faits du style d'un paragraphe.
  static void _paragraphFacts(
    RenderParagraph paragraph,
    Map<String, String> facts,
  ) {
    final TextStyle? style = _effectiveStyle(paragraph.text);
    if (style == null) {
      return;
    }
    final Color? color = style.color;
    if (color != null) {
      facts['textColor'] = _color(color);
    }
    if (style.fontSize != null) {
      facts['fontSize'] = _number(style.fontSize!);
    }
    if (style.fontWeight != null) {
      facts['fontWeight'] = style.fontWeight!.toString();
    }
  }

  /// Le style reellement applique a un paragraphe.
  ///
  /// Le widget `Text` fusionne le style par defaut et le style declare avant
  /// de construire son span : le style du span est donc le style effectif.
  static TextStyle? _effectiveStyle(InlineSpan span) =>
      span is TextSpan ? span.style : null;

  /// Les faits du rayon d'une decoration.
  static String _radiusFacts(BorderRadius radius) {
    final List<Radius> corners = <Radius>[
      radius.topLeft,
      radius.topRight,
      radius.bottomLeft,
      radius.bottomRight,
    ];
    return _cornersFacts(corners);
  }

  /// Les faits du rayon d'une forme.
  ///
  /// Seule la forme a coins arrondis porte un rayon lisible : les autres
  /// formes n'ont pas de rayon propre.
  static String _shapeRadiusFacts(ShapeBorder shape) {
    if (shape is RoundedRectangleBorder) {
      final BorderRadiusGeometry radius = shape.borderRadius;
      if (radius is BorderRadius) {
        return _radiusFacts(radius);
      }
    }
    return '';
  }

  /// Les faits des quatre coins d'un rayon.
  static String _cornersFacts(List<Radius> corners) {
    final Radius first = corners.first;
    final bool isUniform = corners.every(
      (Radius corner) => corner.x == first.x && corner.y == first.y,
    );
    if (isUniform) {
      return _number(first.x);
    }
    return corners
        .map((Radius corner) => '${_number(corner.x)},${_number(corner.y)}')
        .join('/');
  }

  /// Les faits d'une bordure.
  static String _borderFacts(BoxBorder border) {
    final List<BorderSide> sides = switch (border) {
      Border() => <BorderSide>[
        border.top,
        border.right,
        border.bottom,
        border.left,
      ],
      BorderDirectional() => <BorderSide>[
        border.top,
        border.end,
        border.bottom,
        border.start,
      ],
      _ => const <BorderSide>[],
    };
    if (sides.isEmpty) {
      return border.runtimeType.toString();
    }
    final BorderSide first = sides.first;
    final bool isUniform = sides.every(
      (BorderSide side) =>
          side.width == first.width && side.color == first.color,
    );
    if (isUniform) {
      return '${_number(first.width)} ${_color(first.color)}';
    }
    return sides
        .map(
          (BorderSide side) => '${_number(side.width)} ${_color(side.color)}',
        )
        .join('/');
  }

  /// Le nom de la forme d'un modele physique.
  static String _shapeName(ShapeBorder shape) {
    final String name = shape.runtimeType.toString();
    final int bracket = name.indexOf('<');
    return bracket == -1 ? name : name.substring(0, bracket);
  }

  /// Une couleur, en hexadecimal opaque.
  static String _color(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';

  /// Un nombre, sans zeros inutiles.
  static String _number(double value) {
    final String text = value.toStringAsFixed(2);
    final String trimmed = text.contains('.')
        ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : text;
    return trimmed.isEmpty ? '0' : trimmed;
  }
}
