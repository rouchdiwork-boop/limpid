import 'package:flutter/material.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Wraps a widget in a [MaterialApp] built with the Limpid theme.
///
/// Every widget test of the package uses this helper so that the tokens and
/// the theme extension are always available.
Widget wrapWithLimpid(
  Widget child, {
  LimpidThemeVariant variant = LimpidThemeVariant.paper,
  bool withScaffold = true,
}) {
  return MaterialApp(
    theme: LimpidTheme.of(variant),
    home: withScaffold ? Scaffold(body: Center(child: child)) : child,
  );
}
