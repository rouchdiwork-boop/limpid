import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';

/// The modal dialog of the Limpid design system.
///
/// Use [LimpidDialog.show] to display it: the dialog traps the focus, is
/// dismissed with the escape key and announces its title to screen readers.
class LimpidDialog extends StatelessWidget {
  /// Creates a dialog.
  const LimpidDialog({
    super.key,
    required this.child,
    this.title,
    this.actions = const <Widget>[],
    this.icon,
    this.maxWidth = 520,
  });

  /// The content of the dialog.
  final Widget child;

  /// The title of the dialog.
  final String? title;

  /// The actions displayed at the bottom of the dialog.
  final List<Widget> actions;

  /// An optional icon displayed above the title.
  final IconData? icon;

  /// The maximum width of the dialog, in logical pixels.
  final double maxWidth;

  /// Displays the dialog and returns the value passed to [Navigator.pop].
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? title,
    List<Widget> actions = const <Widget>[],
    IconData? icon,
    bool barrierDismissible = true,
    bool useRootNavigator = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      builder: (BuildContext context) => LimpidDialog(
        title: title,
        icon: icon,
        actions: actions,
        child: Builder(builder: builder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: tokens.colors.bgRaised,
      surfaceTintColor: tokens.colors.bgRaised,
      insetPadding: EdgeInsets.all(tokens.spacing.space24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radii.lg),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 24, color: tokens.colors.accent),
                SizedBox(height: tokens.spacing.space12),
              ],
              if (title != null) ...<Widget>[
                Text(title!, style: textTheme.titleLarge),
                SizedBox(height: tokens.spacing.space16),
              ],
              Flexible(child: child),
              if (actions.isNotEmpty) ...<Widget>[
                SizedBox(height: tokens.spacing.space24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The modal bottom sheet of the Limpid design system.
class LimpidBottomSheet extends StatelessWidget {
  /// Creates a bottom sheet.
  const LimpidBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.actions = const <Widget>[],
  });

  /// The content of the sheet.
  final Widget child;

  /// The title of the sheet.
  final String? title;

  /// The actions displayed at the bottom of the sheet.
  final List<Widget> actions;

  /// Displays the sheet and returns the value passed to [Navigator.pop].
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? title,
    List<Widget> actions = const <Widget>[],
    bool isScrollControlled = true,
    bool isDismissible = true,
    bool useSafeArea = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      useSafeArea: useSafeArea,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (BuildContext context) => LimpidBottomSheet(
        title: title,
        actions: actions,
        child: Builder(builder: builder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (title != null) ...<Widget>[
              Text(title!, style: textTheme.titleLarge),
              SizedBox(height: tokens.spacing.space16),
            ],
            Flexible(child: child),
            if (actions.isNotEmpty) ...<Widget>[
              SizedBox(height: tokens.spacing.space24),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// The navigation drawer of the Limpid design system.
class LimpidDrawer extends StatelessWidget {
  /// Creates a drawer.
  const LimpidDrawer({super.key, required this.child, this.header, this.width});

  /// The content of the drawer.
  final Widget child;

  /// An optional widget displayed above the content.
  final Widget? header;

  /// The width of the drawer, in logical pixels.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;

    return Drawer(
      backgroundColor: tokens.colors.bgSurface,
      surfaceTintColor: tokens.colors.bgSurface,
      elevation: 1,
      width: width,
      shape: const RoundedRectangleBorder(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (header != null) ...<Widget>[
            header!,
            Divider(color: tokens.colors.borderSubtle, height: 1),
          ],
          Flexible(child: child),
        ],
      ),
    );
  }
}
