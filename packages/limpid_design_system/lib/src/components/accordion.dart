import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';
import 'package:limpid_design_system/src/tokens/colors.dart';

/// The accordion of the Limpid design system.
///
/// It is an [ExpansionTile] with the decoration of the design system: a flat
/// surface, a hairline border and no shadow.
class LimpidAccordion extends StatelessWidget {
  /// Creates an accordion.
  const LimpidAccordion({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.isExpanded = false,
    this.onExpansionChanged,
    this.trailing,
  });

  /// The title of the accordion.
  final String title;

  /// The content revealed when the accordion is expanded.
  final Widget child;

  /// An optional secondary line displayed under the title.
  final String? subtitle;

  /// An optional leading widget.
  final Widget? leading;

  /// Whether the accordion is expanded.
  final bool isExpanded;

  /// Called when the accordion is expanded or collapsed.
  final ValueChanged<bool>? onExpansionChanged;

  /// An optional trailing widget, replacing the default chevron.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.bgSurface,
        borderRadius: BorderRadius.circular(tokens.radii.md),
        border: Border.all(color: tokens.colors.borderSubtle),
      ),
      child: Theme(
        data: Theme.of(
          context,
        ).copyWith(dividerColor: LimpidColors.transparent),
        child: ExpansionTile(
          title: Text(title, style: textTheme.titleSmall),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.colors.fgMuted,
                  ),
                ),
          leading: leading,
          trailing: trailing,
          initiallyExpanded: isExpanded,
          onExpansionChanged: onExpansionChanged,
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: tokens.colors.accent,
          collapsedIconColor: tokens.colors.fgMuted,
          childrenPadding: EdgeInsets.fromLTRB(
            tokens.spacing.space16,
            0,
            tokens.spacing.space16,
            tokens.spacing.space16,
          ),
          children: <Widget>[child],
        ),
      ),
    );
  }
}
