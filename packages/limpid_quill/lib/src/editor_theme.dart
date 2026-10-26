import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show
        DefaultListBlockStyle,
        DefaultStyles,
        DefaultTextBlockStyle,
        HorizontalSpacing,
        InlineCodeStyle,
        VerticalSpacing;
import 'package:limpid_design_system/limpid_design_system.dart';

/// The typographic presets of the manuscript editor.
///
/// The four presets are listed in DESIGN_SYSTEM.md § 11.1.
enum LimpidEditorPreset {
  /// *Confort* — Literata 18/32. The default writing rhythm.
  comfortable,

  /// *Dense* — Literata 16/28. More text on the screen.
  dense,

  /// *Écran* — Literata 16/26. The tightest rhythm, for narrow windows.
  screen,

  /// *Typographique* — Literata 20/38. The most generous rhythm.
  typographic,
}

/// The type scale of the manuscript editor.
///
/// The presets reuse the type tokens of the design system whenever they
/// exist: *Confort* is the `manuscript` token, *Dense* the `manuscriptSm`
/// token and *Écran* the metrics of the `bodyL` token set in Literata.
///
/// The design system does not ship the *Typographique* preset, so
/// `limpid_quill` owns it as an editor token; its family, weight and letter
/// spacing still come from the design system.
abstract final class LimpidEditorTypography {
  const LimpidEditorTypography._();

  /// The name of the editor token of the *Typographique* preset.
  static const String typographicTokenName = 'editorTypographic';

  /// The *Confort* preset: the `manuscript` token of the design system.
  static LimpidTypeToken get comfortable =>
      LimpidTypography.token('manuscript');

  /// The *Dense* preset: the `manuscriptSm` token of the design system.
  static LimpidTypeToken get dense => LimpidTypography.token('manuscriptSm');

  /// The *Écran* preset: the metrics of the `bodyL` token, in Literata.
  static LimpidTypeToken get screen {
    final LimpidTypeToken bodyLarge = LimpidTypography.token('bodyL');
    return LimpidTypeToken(
      name: 'editorScreen',
      family: LimpidFontFamily.manuscript,
      size: bodyLarge.size,
      lineHeight: bodyLarge.lineHeight,
      weight: FontWeight.w400,
      letterSpacing: 0,
    );
  }

  /// The *Typographique* preset, owned by the editor.
  static final LimpidTypeToken typographic = _buildTypographic();

  /// The token of [preset].
  static LimpidTypeToken tokenOf(LimpidEditorPreset preset) => switch (preset) {
    LimpidEditorPreset.comfortable => comfortable,
    LimpidEditorPreset.dense => dense,
    LimpidEditorPreset.screen => screen,
    LimpidEditorPreset.typographic => typographic,
  };

  static LimpidTypeToken _buildTypographic() {
    final LimpidTypeToken manuscript = LimpidTypography.token('manuscript');
    return LimpidTypeToken(
      name: typographicTokenName,
      family: manuscript.family,
      size: 20,
      lineHeight: 38,
      weight: manuscript.weight,
      letterSpacing: manuscript.letterSpacing,
    );
  }
}

/// The theme of the manuscript editor.
///
/// It carries the typography of the active [LimpidEditorPreset] and builds
/// the block styles handed over to `flutter_quill`. Every colour, spacing
/// and radius comes from the design system tokens.
@immutable
class LimpidEditorTheme {
  /// Creates an editor theme.
  const LimpidEditorTheme({
    required this.preset,
    required this.colors,
    required this.spacing,
    required this.radii,
    required this.type,
  });

  /// Builds the theme from the design system tokens of [context].
  factory LimpidEditorTheme.of(
    BuildContext context, {
    LimpidEditorPreset preset = LimpidEditorPreset.comfortable,
  }) {
    final LimpidThemeScope scope = context.limpid;
    return LimpidEditorTheme(
      preset: preset,
      colors: scope.colors,
      spacing: scope.spacing,
      radii: scope.radii,
      type: LimpidEditorTypography.tokenOf(preset),
    );
  }

  /// The number of characters of a manuscript line (DESIGN_SYSTEM § 11.1).
  static const int measureCharacters = 65;

  /// The approximate advance width of a manuscript glyph, as a fraction of
  /// the font size: the lowercase average of Literata is close to half an
  /// em.
  static const double averageGlyphWidthRatio = 0.5;

  /// The active typographic preset.
  final LimpidEditorPreset preset;

  /// The colour palette of the active theme.
  final LimpidColors colors;

  /// The spacing scale of the active theme.
  final LimpidSpacing spacing;

  /// The radius scale of the active theme.
  final LimpidRadii radii;

  /// The type token of the manuscript body.
  final LimpidTypeToken type;

  /// The style of the manuscript body text.
  TextStyle get bodyStyle => type.toStyle(color: colors.fgDefault);

  /// The height of a manuscript line, in logical pixels.
  double get lineHeight => type.lineHeight;

  /// The width of the manuscript column, in logical pixels.
  double get measureWidth =>
      type.size * averageGlyphWidthRatio * measureCharacters;

  /// The block styles handed over to `flutter_quill`.
  DefaultStyles get defaultStyles => _buildDefaultStyles();

  DefaultStyles _buildDefaultStyles() {
    final TextStyle body = bodyStyle;
    final TextStyle code = _codeStyle;
    return DefaultStyles(
      paragraph: _block(body, bottom: spacing.space8),
      h1: _block(
        _headingStyle('titleL'),
        top: spacing.space32,
        bottom: spacing.space12,
      ),
      h2: _block(
        _headingStyle('titleM'),
        top: spacing.space24,
        bottom: spacing.space8,
      ),
      h3: _block(
        _headingStyle('titleS'),
        top: spacing.space20,
        bottom: spacing.space8,
      ),
      lists: DefaultListBlockStyle(
        body,
        HorizontalSpacing.zero,
        VerticalSpacing(spacing.space4, spacing.space4),
        VerticalSpacing.zero,
        null,
        null,
      ),
      quote: _block(
        body.copyWith(fontStyle: FontStyle.italic),
        top: spacing.space8,
        bottom: spacing.space8,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: colors.secondary)),
        ),
      ),
      code: _block(
        code,
        top: spacing.space8,
        bottom: spacing.space8,
        decoration: BoxDecoration(
          color: colors.bgSunken,
          borderRadius: BorderRadius.circular(radii.xs),
        ),
      ),
      indent: _block(body),
      align: _block(body),
      placeHolder: _block(body.copyWith(color: colors.fgSubtle)),
      bold: body.copyWith(fontWeight: FontWeight.w700),
      italic: body.copyWith(fontStyle: FontStyle.italic),
      underline: body.copyWith(decoration: TextDecoration.underline),
      strikeThrough: body.copyWith(decoration: TextDecoration.lineThrough),
      small: body.copyWith(fontSize: LimpidTypography.token('bodyS').size),
      link: body.copyWith(
        color: colors.secondary,
        decoration: TextDecoration.underline,
      ),
      inlineCode: InlineCodeStyle(
        style: code,
        backgroundColor: colors.bgSunken,
        radius: Radius.circular(radii.xs),
      ),
    );
  }

  TextStyle _headingStyle(String tokenName) {
    final LimpidTypeToken token = LimpidTypography.token(tokenName);
    return TextStyle(
      fontFamily: token.family,
      fontSize: token.size,
      height: token.lineHeightRatio,
      fontWeight: token.weight,
      letterSpacing: token.letterSpacing,
      color: colors.fgDefault,
    );
  }

  TextStyle get _codeStyle {
    final LimpidTypeToken token = LimpidTypography.token('mono');
    return TextStyle(
      fontFamily: token.family,
      fontSize: token.size,
      height: token.lineHeightRatio,
      fontWeight: token.weight,
      letterSpacing: token.letterSpacing,
      color: colors.fgDefault,
    );
  }

  DefaultTextBlockStyle _block(
    TextStyle style, {
    double top = 0,
    double bottom = 0,
    BoxDecoration? decoration,
  }) {
    return DefaultTextBlockStyle(
      style,
      HorizontalSpacing.zero,
      VerticalSpacing(top, bottom),
      VerticalSpacing.zero,
      decoration,
    );
  }
}
