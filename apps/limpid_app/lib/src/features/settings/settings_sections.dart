import 'package:flutter/material.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// A titled group of settings.
///
/// The section owns the card, the dividers and the uppercase title: the
/// screen only provides the rows.
class SettingsSection extends StatelessWidget {
  /// Creates a section.
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  /// The title of the section.
  final String title;

  /// The rows of the section.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            left: scope.spacing.space4,
            bottom: scope.spacing.space8,
          ),
          child: Text(
            LimpidTextTransform.label(title),
            style: LimpidTypography.labelStyle(color: scope.colors.fgSubtle),
          ),
        ),
        LimpidCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var index = 0; index < children.length; index++) ...<Widget>[
                children[index],
                if (index < children.length - 1)
                  Divider(
                    height: 1,
                    color: scope.colors.borderSubtle,
                    indent: scope.spacing.space16,
                    endIndent: scope.spacing.space16,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A row that selects a theme variant.
///
/// The row shows the palette of the variant next to its name: the author
/// sees the theme before applying it.
class ThemeVariantRow extends StatelessWidget {
  /// Creates a row.
  const ThemeVariantRow({
    super.key,
    required this.label,
    required this.variant,
    required this.isSelected,
    required this.onTap,
  });

  /// The name of the variant.
  final String label;

  /// The variant the row applies.
  final LimpidThemeVariant variant;

  /// Whether the variant is the active one.
  final bool isSelected;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final LimpidColors swatch = variant.colors;

    return Semantics(
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(scope.radii.sm),
        child: Container(
          constraints: BoxConstraints(minHeight: scope.spacing.space48),
          padding: EdgeInsets.symmetric(horizontal: scope.spacing.space12),
          decoration: BoxDecoration(
            color: isSelected ? scope.colors.accentSubtle : null,
            borderRadius: BorderRadius.circular(scope.radii.sm),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: scope.spacing.space24,
                height: scope.spacing.space24,
                decoration: BoxDecoration(
                  color: swatch.bgCanvas,
                  borderRadius: BorderRadius.circular(scope.radii.sm),
                  border: Border.all(
                    color: isSelected
                        ? scope.colors.accent
                        : scope.colors.borderDefault,
                    width: isSelected ? 2 : 1,
                  ),
                ),
              ),
              SizedBox(width: scope.spacing.space12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isSelected
                        ? scope.colors.accent
                        : scope.colors.fgDefault,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  LimpidIcons.check,
                  size: scope.spacing.space16,
                  color: scope.colors.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
