import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/tokens/colors.dart';
import 'package:limpid_design_system/src/tokens/radii.dart';
import 'package:limpid_design_system/src/tokens/spacing.dart';

/// The inputs needed to build the component themes of the design system.
@immutable
class LimpidThemeInput {
  /// Creates a theme input.
  const LimpidThemeInput({
    required this.colors,
    required this.textTheme,
    required this.radii,
    required this.spacing,
    required this.isDark,
  });

  /// The color palette.
  final LimpidColors colors;

  /// The text theme.
  final TextTheme textTheme;

  /// The radius scale.
  final LimpidRadii radii;

  /// The spacing scale.
  final LimpidSpacing spacing;

  /// Whether the active variant is a dark one.
  final bool isDark;
}

/// Builds the Material component themes of the Limpid design system.
///
/// The Material defaults are never left untouched: every component theme is
/// derived from the tokens so that the four variants stay consistent.
abstract final class LimpidComponentThemes {
  /// Minimum size of an interactive target, in logical pixels.
  static const double minTapTarget = 44;

  /// The theme of the app bar.
  static AppBarThemeData appBar(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return AppBarThemeData(
      backgroundColor: colors.bgCanvas,
      foregroundColor: colors.fgDefault,
      surfaceTintColor: colors.bgCanvas,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: input.textTheme.titleLarge,
    );
  }

  /// The theme of cards.
  static CardThemeData card(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return CardThemeData(
      color: colors.bgSurface,
      surfaceTintColor: colors.bgSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(input.radii.md),
        side: BorderSide(color: colors.borderSubtle),
      ),
    );
  }

  /// The theme of dialogs.
  static DialogThemeData dialog(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return DialogThemeData(
      backgroundColor: colors.bgRaised,
      surfaceTintColor: colors.bgRaised,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(input.radii.lg),
      ),
      titleTextStyle: input.textTheme.titleLarge,
      contentTextStyle: input.textTheme.bodyMedium,
    );
  }

  /// The theme of bottom sheets.
  static BottomSheetThemeData bottomSheet(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return BottomSheetThemeData(
      backgroundColor: colors.bgRaised,
      modalBackgroundColor: colors.bgRaised,
      surfaceTintColor: colors.bgRaised,
      elevation: 3,
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(input.radii.xl),
        ),
      ),
    );
  }

  /// The theme of drawers.
  static DrawerThemeData drawer(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return DrawerThemeData(
      backgroundColor: colors.bgSurface,
      surfaceTintColor: colors.bgSurface,
      elevation: 1,
      shape: const RoundedRectangleBorder(),
    );
  }

  /// The theme of snack bars.
  static SnackBarThemeData snackBar(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.fgDefault,
      contentTextStyle: input.textTheme.bodyMedium?.copyWith(
        color: colors.bgSurface,
      ),
      actionTextColor: colors.accent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(input.radii.md),
      ),
    );
  }

  /// The theme of tooltips.
  static TooltipThemeData tooltip(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.fgDefault,
        borderRadius: BorderRadius.circular(input.radii.xs),
      ),
      textStyle: input.textTheme.bodySmall?.copyWith(color: colors.bgSurface),
      padding: EdgeInsets.symmetric(
        horizontal: input.spacing.space8,
        vertical: input.spacing.space4,
      ),
      waitDuration: const Duration(milliseconds: 400),
    );
  }

  /// The theme of dividers.
  static DividerThemeData divider(LimpidThemeInput input) {
    return DividerThemeData(
      color: input.colors.borderSubtle,
      thickness: 1,
      space: 1,
    );
  }

  /// The theme of pop-up menus.
  static PopupMenuThemeData popupMenu(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return PopupMenuThemeData(
      color: colors.bgRaised,
      surfaceTintColor: colors.bgRaised,
      elevation: 3,
      textStyle: input.textTheme.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(input.radii.md),
        side: BorderSide(color: colors.borderSubtle),
      ),
    );
  }

  /// The theme of tabs.
  static TabBarThemeData tabBar(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return TabBarThemeData(
      labelColor: colors.accent,
      unselectedLabelColor: colors.fgMuted,
      indicatorColor: colors.accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: colors.borderSubtle,
      labelStyle: input.textTheme.titleSmall,
      unselectedLabelStyle: input.textTheme.titleSmall,
      labelPadding: EdgeInsets.symmetric(
        horizontal: input.spacing.space12,
        vertical: input.spacing.space8,
      ),
    );
  }

  /// The theme of list tiles.
  static ListTileThemeData listTile(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return ListTileThemeData(
      iconColor: colors.fgMuted,
      textColor: colors.fgDefault,
      titleTextStyle: input.textTheme.bodyLarge,
      subtitleTextStyle: input.textTheme.bodySmall?.copyWith(
        color: colors.fgMuted,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: input.spacing.space16,
        vertical: input.spacing.space4,
      ),
    );
  }

  /// The theme of chips.
  static ChipThemeData chip(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return ChipThemeData(
      backgroundColor: colors.bgSunken,
      selectedColor: colors.accentSubtle,
      disabledColor: colors.bgSunken,
      showCheckmark: false,
      side: BorderSide(color: colors.borderSubtle),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(input.radii.pill),
      ),
      labelStyle: input.textTheme.labelMedium?.copyWith(
        color: colors.fgDefault,
      ),
      secondaryLabelStyle: input.textTheme.labelMedium?.copyWith(
        color: colors.fgDefault,
      ),
      deleteIconColor: colors.fgMuted,
      padding: EdgeInsets.symmetric(
        horizontal: input.spacing.space8,
        vertical: input.spacing.space4,
      ),
    );
  }

  /// The theme of checkboxes.
  static CheckboxThemeData checkbox(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.bgSunken;
        }
        if (states.contains(WidgetState.selected)) {
          return colors.accent;
        }
        return colors.bgSurface;
      }),
      checkColor: WidgetStatePropertyAll<Color?>(colors.fgOnAccent),
      side: BorderSide(color: colors.borderStrong),
    );
  }

  /// The theme of radio buttons.
  static RadioThemeData radio(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.bgSunken;
        }
        if (states.contains(WidgetState.selected)) {
          return colors.accent;
        }
        return colors.bgSurface;
      }),
      side: BorderSide(color: colors.borderStrong),
    );
  }

  /// The theme of switches.
  static SwitchThemeData switchTheme(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.fgSubtle;
        }
        if (states.contains(WidgetState.selected)) {
          return colors.fgOnAccent;
        }
        return colors.bgSurface;
      }),
      trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.bgSunken;
        }
        if (states.contains(WidgetState.selected)) {
          return colors.accent;
        }
        return colors.bgSunken;
      }),
      trackOutlineColor: WidgetStatePropertyAll<Color?>(colors.borderStrong),
    );
  }

  /// The theme of sliders.
  static SliderThemeData slider(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return SliderThemeData(
      trackHeight: 4,
      activeTrackColor: colors.accent,
      inactiveTrackColor: colors.bgSunken,
      thumbColor: colors.accent,
      overlayColor: colors.accent.withValues(alpha: 0.12),
      valueIndicatorColor: colors.fgDefault,
      valueIndicatorTextStyle: input.textTheme.labelSmall?.copyWith(
        color: colors.bgSurface,
      ),
    );
  }

  /// The theme of segmented buttons.
  static SegmentedButtonThemeData segmentedButton(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size(0, minTapTarget)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colors.accentSubtle
              : colors.bgSurface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? colors.accent
              : colors.fgMuted,
        ),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: colors.borderDefault),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(input.radii.sm),
          ),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          input.textTheme.labelMedium,
        ),
      ),
    );
  }

  /// The theme of icon buttons.
  static IconButtonThemeData iconButton(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(
          Size(minTapTarget, minTapTarget),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => states.contains(WidgetState.disabled)
              ? colors.fgSubtle
              : colors.fgDefault,
        ),
        overlayColor: WidgetStatePropertyAll<Color?>(
          colors.accent.withValues(alpha: 0.10),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(input.radii.sm),
          ),
        ),
      ),
    );
  }

  /// The theme of data tables.
  static DataTableThemeData dataTable(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return DataTableThemeData(
      headingTextStyle: input.textTheme.labelMedium?.copyWith(
        color: colors.fgMuted,
      ),
      dataTextStyle: input.textTheme.bodyMedium?.copyWith(
        color: colors.fgDefault,
      ),
      headingRowColor: WidgetStatePropertyAll<Color?>(colors.bgSunken),
      dividerThickness: 1,
    );
  }

  /// The theme of progress indicators.
  static ProgressIndicatorThemeData progressIndicator(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.bgSunken,
      circularTrackColor: colors.bgSunken,
      linearMinHeight: 4,
    );
  }

  /// The theme of text selections.
  static TextSelectionThemeData textSelection(LimpidThemeInput input) {
    final LimpidColors colors = input.colors;
    return TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accent.withValues(alpha: 0.24),
      selectionHandleColor: colors.accent,
    );
  }
}
