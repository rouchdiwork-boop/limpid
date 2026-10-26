import 'dart:async';

import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/components/status.dart';
import 'package:limpid_design_system/src/icons/limpid_icons.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';

/// The linear progress indicator of the Limpid design system.
class LimpidLinearProgress extends StatelessWidget {
  /// Creates a linear progress indicator.
  ///
  /// A null [value] displays an indeterminate indicator.
  const LimpidLinearProgress({super.key, this.value, this.label});

  /// The progress between 0 and 1, or null when indeterminate.
  final double? value;

  /// An optional label displayed above the bar.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: label,
      value: value == null ? null : '${(value! * 100).round()}%',
      child: Column(
        // La barre occupe toute la largeur disponible : sans cela,
        // LinearProgressIndicator reçoit des contraintes lâches et déborde.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (label != null) ...<Widget>[
            Text(label!, style: textTheme.labelMedium),
            SizedBox(height: tokens.spacing.space8),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radii.pill),
            child: LinearProgressIndicator(value: value),
          ),
        ],
      ),
    );
  }
}

/// The circular progress indicator of the Limpid design system.
class LimpidCircularProgress extends StatelessWidget {
  /// Creates a circular progress indicator.
  const LimpidCircularProgress({super.key, this.value, this.size = 24});

  /// The progress between 0 and 1, or null when indeterminate.
  final double? value;

  /// The diameter of the indicator, in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: value == null ? null : '${(value! * 100).round()}%',
      child: SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(value: value, strokeWidth: 2.5),
      ),
    );
  }
}

/// The sizes of a [LimpidSpinner].
enum LimpidSpinnerSize {
  /// A 12 pixel spinner.
  small,

  /// A 16 pixel spinner.
  medium,

  /// A 24 pixel spinner.
  large,
}

/// The inline busy indicator of the Limpid design system.
///
/// It is meant to be placed inside a button, a list row or a card, where a
/// full [LimpidCircularProgress] would be too heavy.
class LimpidSpinner extends StatelessWidget {
  /// Creates a spinner.
  const LimpidSpinner({
    super.key,
    this.size = LimpidSpinnerSize.small,
    this.color,
  });

  /// The size of the spinner.
  final LimpidSpinnerSize size;

  /// An optional color override.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final double dimension = switch (size) {
      LimpidSpinnerSize.small => 12,
      LimpidSpinnerSize.medium => 16,
      LimpidSpinnerSize.large => 24,
    };

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: dimension,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          value: null,
          color: color,
        ),
      ),
    );
  }
}

/// The empty state of the Limpid design system.
///
/// It tells the user that a list has no content yet and, when an action is
/// provided, how to fill it.
class LimpidEmptyState extends StatelessWidget {
  /// Creates an empty state.
  const LimpidEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = LimpidIcons.empty,
    this.action,
  });

  /// The title of the empty state.
  final String title;

  /// An optional secondary line.
  final String? message;

  /// The icon displayed above the title.
  final IconData? icon;

  /// An optional action, usually a [LimpidButton].
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 40, color: tokens.colors.fgSubtle),
                  SizedBox(height: tokens.spacing.space16),
                ],
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium,
                ),
                if (message != null) ...<Widget>[
                  SizedBox(height: tokens.spacing.space8),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.colors.fgMuted,
                    ),
                  ),
                ],
                if (action != null) ...<Widget>[
                  SizedBox(height: tokens.spacing.space24),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The snack bar of the Limpid design system.
///
/// The status is carried by the background color, an icon and the text, so
/// that it never depends on the color alone.
class LimpidSnackbar extends StatelessWidget {
  /// Creates the content of a snack bar.
  const LimpidSnackbar({
    super.key,
    required this.message,
    this.variant = LimpidStatusVariant.neutral,
  });

  /// The text of the snack bar.
  final String message;

  /// The status carried by the snack bar.
  final LimpidStatusVariant variant;

  /// Displays the snack bar.
  static void show(
    BuildContext context, {
    required String message,
    LimpidStatusVariant variant = LimpidStatusVariant.neutral,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 5),
  }) {
    final LimpidThemeScope tokens = context.limpid;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool isNeutral = variant == LimpidStatusVariant.neutral;
    final Color background = isNeutral
        ? tokens.colors.fgDefault
        : LimpidStatusStyle.of(variant, tokens.colors).color;
    final Color foreground = isNeutral
        ? tokens.colors.bgSurface
        : tokens.colors.fgOnAccent;

    final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller =
        messenger.showSnackBar(
          SnackBar(
            duration: duration,
            backgroundColor: background,
            elevation: 3,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radii.md),
            ),
            content: LimpidSnackbar(message: message, variant: variant),
            action: actionLabel == null
                ? null
                : SnackBarAction(
                    label: actionLabel,
                    textColor: foreground,
                    onPressed: onAction ?? () {},
                  ),
          ),
        );
    unawaited(controller.closed.then<void>((_) {}));
  }

  /// Hides the snack bar currently displayed.
  static void hide(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final bool isNeutral = variant == LimpidStatusVariant.neutral;
    final Color foreground = isNeutral
        ? tokens.colors.bgSurface
        : tokens.colors.fgOnAccent;
    final IconData icon = isNeutral
        ? LimpidIcons.info
        : LimpidStatusStyle.of(variant, tokens.colors).icon;

    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: foreground),
        SizedBox(width: tokens.spacing.space12),
        Expanded(
          child: Text(
            message,
            style: textTheme.bodyMedium?.copyWith(color: foreground),
          ),
        ),
      ],
    );
  }
}
