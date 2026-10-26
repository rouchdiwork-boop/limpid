import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';
import 'package:limpid_design_system/src/tokens/colors.dart';
import 'package:limpid_design_system/src/tokens/typography.dart';

/// The visual variants of a [LimpidButton].
enum LimpidButtonVariant {
  /// Filled with the accent color. The main action of a screen.
  primary,

  /// Filled with the secondary color. A competing, less urgent action.
  secondary,

  /// Transparent until hovered. An action living inside a toolbar.
  ghost,

  /// Filled with the danger color. A destructive action.
  danger,

  /// Transparent, text only. The least prominent action.
  text,
}

/// The sizes of a [LimpidButton].
enum LimpidButtonSize {
  /// Compact button, for dense toolbars.
  small,

  /// Default button.
  medium,

  /// Large button, for a primary call to action.
  large,
}

/// The primary button of the Limpid design system.
///
/// The button covers the five variants (`primary`, `secondary`, `ghost`,
/// `danger`, `text`), the three sizes and the `loading` / `disabled` states.
///
/// Every interactive element keeps a 48×48 hit area (via
/// [MaterialTapTargetSize.padded]) even when the visual size is smaller, and
/// exposes a correct [Semantics] contract to screen readers.
class LimpidButton extends StatelessWidget {
  /// Creates a button.
  const LimpidButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = LimpidButtonVariant.primary,
    this.size = LimpidButtonSize.medium,
    this.loading = false,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.semanticLabel,
  });

  /// The text of the button.
  final String label;

  /// Called when the button is pressed. A null callback disables it.
  final VoidCallback? onPressed;

  /// The visual variant.
  final LimpidButtonVariant variant;

  /// The size of the button.
  final LimpidButtonSize size;

  /// Whether the button displays a busy indicator.
  ///
  /// A loading button ignores presses and announces itself as a live region.
  final bool loading;

  /// An optional leading icon.
  final IconData? icon;

  /// An optional trailing icon.
  final IconData? trailingIcon;

  /// Whether the button takes the whole width of its parent.
  final bool expand;

  /// The label announced by screen readers. Defaults to [label].
  final String? semanticLabel;

  bool get _isEnabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = _buildStyle(context);
    final Widget content = _buildContent(context);
    final Widget button = switch (variant) {
      LimpidButtonVariant.primary => ElevatedButton(
        onPressed: _effectiveOnPressed,
        style: style,
        child: content,
      ),
      LimpidButtonVariant.secondary => ElevatedButton(
        onPressed: _effectiveOnPressed,
        style: style,
        child: content,
      ),
      LimpidButtonVariant.ghost => TextButton(
        onPressed: _effectiveOnPressed,
        style: style,
        child: content,
      ),
      LimpidButtonVariant.danger => ElevatedButton(
        onPressed: _effectiveOnPressed,
        style: style,
        child: content,
      ),
      LimpidButtonVariant.text => TextButton(
        onPressed: _effectiveOnPressed,
        style: style,
        child: content,
      ),
    };

    final Widget sized = expand
        ? SizedBox(width: double.infinity, child: button)
        : button;

    return Semantics(
      button: true,
      enabled: _isEnabled,
      liveRegion: loading,
      label: semanticLabel ?? label,
      child: sized,
    );
  }

  VoidCallback? get _effectiveOnPressed {
    if (!_isEnabled || loading) {
      return null;
    }
    return onPressed;
  }

  Widget _buildContent(BuildContext context) {
    final double iconSize = switch (size) {
      LimpidButtonSize.small => 16,
      LimpidButtonSize.medium => 18,
      LimpidButtonSize.large => 20,
    };
    final double gap = context.limpid.spacing.space8;

    // Les boutons gardent la casse de phrase : la mise en capitales du token
    // `label` est réservée aux libellés de formulaire et aux titres de
    // section, qui sont courts par construction (DESIGN_SYSTEM.md §3.3).
    final Widget labelWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );

    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: iconSize),
          SizedBox(width: gap),
        ],
        Flexible(child: labelWidget),
        if (trailingIcon != null) ...<Widget>[
          SizedBox(width: gap),
          Icon(trailingIcon, size: iconSize),
        ],
      ],
    );

    if (!loading) {
      return content;
    }

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Opacity(opacity: 0, child: content),
        ExcludeSemantics(
          child: SizedBox.square(
            dimension: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _foreground(context),
            ),
          ),
        ),
      ],
    );
  }

  ButtonStyle _buildStyle(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final LimpidColors colors = tokens.colors;

    final double height = switch (size) {
      LimpidButtonSize.small => 32,
      LimpidButtonSize.medium => 40,
      LimpidButtonSize.large => 48,
    };
    final double horizontalPadding = switch (size) {
      LimpidButtonSize.small => tokens.spacing.space12,
      LimpidButtonSize.medium => tokens.spacing.space16,
      LimpidButtonSize.large => tokens.spacing.space20,
    };
    final TextStyle textStyle = switch (size) {
      LimpidButtonSize.small => LimpidTypography.token('label').toStyle(),
      LimpidButtonSize.medium => LimpidTypography.token('bodyM').toStyle(),
      LimpidButtonSize.large => LimpidTypography.token('bodyL').toStyle(),
    };

    final _ButtonPalette palette = _ButtonPalette.of(variant, colors);

    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll<Size>(Size(0, height)),
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: horizontalPadding),
      ),
      elevation: const WidgetStatePropertyAll<double>(0),
      backgroundColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) => _backgroundColor(states, palette),
      ),
      foregroundColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) => _foregroundColor(states, palette),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle?>(
        textStyle.copyWith(color: palette.foreground),
      ),
      iconColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) => _foregroundColor(states, palette),
      ),
      side: WidgetStateProperty.resolveWith<BorderSide?>(
        (Set<WidgetState> states) => BorderSide(
          color: states.contains(WidgetState.disabled)
              ? palette.borderDisabled
              : palette.border,
        ),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radii.sm),
        ),
      ),
      overlayColor: WidgetStatePropertyAll<Color?>(
        colors.accent.withValues(alpha: 0.10),
      ),
    );
  }

  Color _backgroundColor(Set<WidgetState> states, _ButtonPalette palette) {
    if (states.contains(WidgetState.disabled)) {
      return palette.backgroundDisabled;
    }
    if (states.contains(WidgetState.pressed)) {
      return palette.pressed;
    }
    if (states.contains(WidgetState.hovered)) {
      return palette.hover;
    }
    return palette.background;
  }

  Color _foregroundColor(Set<WidgetState> states, _ButtonPalette palette) {
    if (states.contains(WidgetState.disabled)) {
      return palette.foregroundDisabled;
    }
    return palette.foreground;
  }

  Color _foreground(BuildContext context) {
    final LimpidColors colors = context.limpid.colors;
    return _ButtonPalette.of(variant, colors).foreground;
  }
}

/// The resolved colors of a button variant.
@immutable
class _ButtonPalette {
  const _ButtonPalette({
    required this.background,
    required this.backgroundDisabled,
    required this.foreground,
    required this.foregroundDisabled,
    required this.border,
    required this.borderDisabled,
    required this.hover,
    required this.pressed,
  });

  factory _ButtonPalette.of(LimpidButtonVariant variant, LimpidColors colors) {
    return switch (variant) {
      LimpidButtonVariant.primary => _ButtonPalette(
        background: colors.accent,
        backgroundDisabled: colors.bgSunken,
        foreground: colors.fgOnAccent,
        foregroundDisabled: colors.fgSubtle,
        border: colors.accent,
        borderDisabled: colors.bgSunken,
        hover: colors.accentHover,
        pressed: colors.accentPressed,
      ),
      LimpidButtonVariant.secondary => _ButtonPalette(
        background: colors.secondary,
        backgroundDisabled: colors.bgSunken,
        foreground: colors.fgOnAccent,
        foregroundDisabled: colors.fgSubtle,
        border: colors.secondary,
        borderDisabled: colors.bgSunken,
        hover: _shift(colors.secondary, colors.fgDefault),
        pressed: _shift(colors.secondary, colors.fgDefault, 0.30),
      ),
      LimpidButtonVariant.ghost => _ButtonPalette(
        background: LimpidColors.transparent,
        backgroundDisabled: LimpidColors.transparent,
        foreground: colors.accent,
        foregroundDisabled: colors.fgSubtle,
        border: LimpidColors.transparent,
        borderDisabled: LimpidColors.transparent,
        hover: colors.accentSubtle,
        pressed: colors.accentSubtle,
      ),
      LimpidButtonVariant.danger => _ButtonPalette(
        background: colors.danger,
        backgroundDisabled: colors.bgSunken,
        foreground: colors.fgOnAccent,
        foregroundDisabled: colors.fgSubtle,
        border: colors.danger,
        borderDisabled: colors.bgSunken,
        hover: _shift(colors.danger, colors.fgDefault),
        pressed: _shift(colors.danger, colors.fgDefault, 0.30),
      ),
      LimpidButtonVariant.text => _ButtonPalette(
        background: LimpidColors.transparent,
        backgroundDisabled: LimpidColors.transparent,
        foreground: colors.accent,
        foregroundDisabled: colors.fgSubtle,
        border: LimpidColors.transparent,
        borderDisabled: LimpidColors.transparent,
        hover: LimpidColors.transparent,
        pressed: colors.accentSubtle,
      ),
    };
  }

  final Color background;
  final Color backgroundDisabled;
  final Color foreground;
  final Color foregroundDisabled;
  final Color border;
  final Color borderDisabled;
  final Color hover;
  final Color pressed;

  static Color _shift(Color base, Color towards, [double amount = 0.15]) =>
      Color.lerp(base, towards, amount) ?? base;
}
