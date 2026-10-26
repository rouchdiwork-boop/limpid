import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Wraps [child] in a [MaterialApp] built with the Limpid design system.
Widget limpidTestApp({
  required Widget child,
  LimpidThemeVariant variant = LimpidThemeVariant.paper,
}) {
  return MaterialApp(
    theme: LimpidTheme.of(variant),
    home: Scaffold(body: child),
  );
}

/// Finds the rich texts of the editor whose content contains [text].
///
/// `flutter_quill` renders the manuscript with rich texts, not with text
/// widgets, so `find.text` cannot be used.
Finder findRichTextContaining(String text) {
  return find.byWidgetPredicate((Widget widget) {
    if (widget is! RichText) {
      return false;
    }
    return widget.text.toPlainText().contains(text);
  });
}
