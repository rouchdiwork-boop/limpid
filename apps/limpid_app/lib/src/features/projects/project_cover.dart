import 'package:flutter/material.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The cover of a book.
///
/// The ratio is 2:3 — the shape of a printed book — and the corners stay
/// almost square (D-11): it is a spine, not a card.
///
/// The typography scales with the cover, so that the same widget works for
/// the 78 px thumbnail of the dashboard and for the 200 px cover of the
/// library.
class ProjectCover extends StatelessWidget {
  /// Creates the cover.
  const ProjectCover({
    required this.title,
    required this.author,
    required this.seed,
    this.width,
    super.key,
  });

  /// The title printed on the cover.
  final String title;

  /// The author printed on the cover.
  final String author;

  /// The index of the palette, which gives every book its own colour.
  final int seed;

  /// The width of the cover. When it is null, the cover fills its parent.
  final double? width;

  /// The number of palettes the covers are drawn from.
  static const int paletteCount = 6;

  /// The ratio between the width of the cover and the size of its title.
  static const double _titleSizeRatio = 0.19;

  /// The ratio between the width of the cover and the size of its author.
  static const double _authorSizeRatio = 0.10;

  /// The smallest size the title of a cover takes.
  static const double _minTitleSize = 9;

  /// The largest size the title of a cover takes.
  static const double _maxTitleSize = 19;

  /// The smallest size the author of a cover takes.
  static const double _minAuthorSize = 7;

  /// The largest size the author of a cover takes.
  static const double _maxAuthorSize = 11;

  /// The ratio of the padding of the cover, against its width.
  static const double _paddingRatio = 0.13;

  /// The smallest padding a cover takes.
  static const double _minPadding = 8;

  /// The largest padding a cover takes.
  static const double _maxPadding = 18;

  /// The share of the gradient the shade takes.
  static const double _shadeRatio = 0.55;

  /// The opacity of the shadow of the cover.
  static const double _shadowOpacity = 0.22;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final LimpidColors colors = scope.colors;
    final Color base = _paletteOf(colors)[seed % paletteCount];
    final Color shade = scope.isDark ? colors.bgCanvas : colors.fgDefault;
    final Color ink = scope.isDark ? colors.fgDefault : colors.bgCanvas;
    final double requested = width ?? 0;
    final bool isBounded = requested.isFinite && requested > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = isBounded
            ? requested
            : (constraints.maxWidth.isFinite ? constraints.maxWidth : 120);
        final double titleSize = (w * _titleSizeRatio).clamp(
          _minTitleSize,
          _maxTitleSize,
        );
        final double authorSize = (w * _authorSizeRatio).clamp(
          _minAuthorSize,
          _maxAuthorSize,
        );
        final double padding = (w * _paddingRatio).clamp(
          _minPadding,
          _maxPadding,
        );

        final Widget content = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(scope.radii.sm),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[base, Color.lerp(base, shade, _shadeRatio)!],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.fgDefault.withValues(alpha: _shadowOpacity),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Flexible(
                  child: Text(
                    title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: ink,
                      fontFamily: LimpidFontFamily.manuscript,
                      fontWeight: FontWeight.w600,
                      fontSize: titleSize,
                      height: 1.15,
                    ),
                  ),
                ),
                Text(
                  author.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ink.withValues(alpha: 0.82),
                    letterSpacing: 1.1,
                    fontSize: authorSize,
                  ),
                ),
              ],
            ),
          ),
        );

        return Semantics(
          image: true,
          label: author.isEmpty ? title : '$title, $author',
          child: isBounded
              ? SizedBox(
                  width: requested,
                  height: requested * 1.5,
                  child: content,
                )
              : SizedBox.expand(child: content),
        );
      },
    );
  }

  /// The palettes the covers are drawn from.
  ///
  /// The colours come from the tokens of the theme: every book keeps its own
  /// hue, in every theme.
  static List<Color> _paletteOf(LimpidColors colors) => <Color>[
    colors.accent,
    colors.secondary,
    colors.success,
    colors.warning,
    colors.danger,
    colors.info,
  ];
}
