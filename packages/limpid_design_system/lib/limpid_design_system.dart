/// The Limpid design system.
///
/// This package is the single source of truth of the visual identity of
/// Limpid: the design tokens, the four themes and the reusable `Limpid*`
/// widgets.
///
/// ```dart
/// MaterialApp(
///   theme: LimpidTheme.of(LimpidThemeVariant.paper),
///   home: const HomePage(),
/// );
/// ```
///
/// Inside a screen, the tokens are reachable with `context.limpid` and the
/// widgets are always prefixed with `Limpid`.
library;

export 'package:limpid_design_system/src/components/accordion.dart';
export 'package:limpid_design_system/src/components/avatar.dart';
export 'package:limpid_design_system/src/components/buttons.dart';
export 'package:limpid_design_system/src/components/command_palette.dart';
export 'package:limpid_design_system/src/components/combobox.dart';
export 'package:limpid_design_system/src/components/data_table.dart';
export 'package:limpid_design_system/src/components/dialogs.dart';
export 'package:limpid_design_system/src/components/editor_blocks.dart';
export 'package:limpid_design_system/src/components/feedback.dart';
export 'package:limpid_design_system/src/components/icon_button.dart';
export 'package:limpid_design_system/src/components/navigation.dart';
export 'package:limpid_design_system/src/components/overlays.dart';
export 'package:limpid_design_system/src/components/selection.dart';
export 'package:limpid_design_system/src/components/status.dart';
export 'package:limpid_design_system/src/components/stepper.dart';
export 'package:limpid_design_system/src/components/surfaces.dart';
export 'package:limpid_design_system/src/components/text_inputs.dart';
export 'package:limpid_design_system/src/components/toggles.dart';
export 'package:limpid_design_system/src/icons/limpid_icons.dart';
export 'package:limpid_design_system/src/theme/limpid_theme.dart';
export 'package:limpid_design_system/src/tokens/colors.dart';
export 'package:limpid_design_system/src/tokens/elevation.dart';
export 'package:limpid_design_system/src/tokens/motion.dart';
export 'package:limpid_design_system/src/tokens/radii.dart';
export 'package:limpid_design_system/src/tokens/spacing.dart';
export 'package:limpid_design_system/src/tokens/typography.dart';
