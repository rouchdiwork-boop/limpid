import 'package:flutter/material.dart';

/// The single line text field of the Limpid design system.
///
/// The decoration (border, focus ring, helper and error styles) comes from
/// the theme built by `LimpidTheme.of`, so a field never needs a local
/// style.
class LimpidTextField extends StatelessWidget {
  /// Creates a text field.
  const LimpidTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.prefixIcon,
    this.suffixIcon,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.semanticLabel,
    this.focusedSemanticLabel,
  });

  /// The controller of the field.
  final TextEditingController? controller;

  /// The floating label of the field.
  final String? label;

  /// The placeholder text.
  final String? hint;

  /// The helper text displayed below the field.
  final String? helperText;

  /// The error text. When set, the field is displayed as invalid.
  final String? errorText;

  /// Called whenever the value changes.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits the value.
  final ValueChanged<String>? onSubmitted;

  /// The focus node of the field.
  final FocusNode? focusNode;

  /// An optional leading icon.
  final IconData? prefixIcon;

  /// An optional trailing icon.
  final IconData? suffixIcon;

  /// An optional trailing widget, used for instance by the search field.
  final Widget? suffix;

  /// The type of keyboard to display.
  final TextInputType? keyboardType;

  /// The action button of the keyboard.
  final TextInputAction? textInputAction;

  /// Whether the content is hidden.
  final bool obscureText;

  /// Whether the field accepts input.
  final bool enabled;

  /// Whether the field is read only.
  final bool readOnly;

  /// Whether the field takes the focus on first build.
  final bool autofocus;

  /// The maximum number of lines.
  final int? maxLines;

  /// The minimum number of lines.
  final int? minLines;

  /// The capitalization applied to the input.
  final TextCapitalization textCapitalization;

  /// The autofill hints of the field.
  final Iterable<String>? autofillHints;

  /// The label announced by screen readers.
  final String? semanticLabel;

  /// The label announced when the field is focused.
  final String? focusedSemanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: semanticLabel ?? label,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        obscureText: obscureText,
        enabled: enabled,
        readOnly: readOnly,
        autofocus: autofocus,
        maxLines: maxLines,
        minLines: minLines,
        textCapitalization: textCapitalization,
        autofillHints: autofillHints,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          errorText: errorText,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
          suffixIcon: suffixIcon == null ? null : Icon(suffixIcon),
          suffix: suffix,
        ),
      ),
    );
  }
}

/// The multi line text field of the Limpid design system.
///
/// It shares the decoration of [LimpidTextField] and aligns its content to
/// the top, the way a writing tool does.
class LimpidTextArea extends StatelessWidget {
  /// Creates a text area.
  const LimpidTextArea({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.minLines = 3,
    this.maxLines = 8,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.sentences,
    this.semanticLabel,
  });

  /// The controller of the text area.
  final TextEditingController? controller;

  /// The floating label of the text area.
  final String? label;

  /// The placeholder text.
  final String? hint;

  /// The helper text displayed below the text area.
  final String? helperText;

  /// The error text.
  final String? errorText;

  /// Called whenever the value changes.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits the value.
  final ValueChanged<String>? onSubmitted;

  /// The focus node of the text area.
  final FocusNode? focusNode;

  /// The minimum number of lines.
  final int minLines;

  /// The maximum number of lines. Null means the text area can grow.
  final int? maxLines;

  /// Whether the text area accepts input.
  final bool enabled;

  /// Whether the text area is read only.
  final bool readOnly;

  /// Whether the text area takes the focus on first build.
  final bool autofocus;

  /// The capitalization applied to the input.
  final TextCapitalization textCapitalization;

  /// The label announced by screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: semanticLabel ?? label,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        minLines: minLines,
        maxLines: maxLines,
        enabled: enabled,
        readOnly: readOnly,
        autofocus: autofocus,
        textCapitalization: textCapitalization,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          errorText: errorText,
          alignLabelWithHint: true,
        ),
      ),
    );
  }
}

/// The search field of the Limpid design system.
///
/// It adds a leading search icon and a clear button that appears as soon as
/// the field holds a value.
class LimpidSearchField extends StatefulWidget {
  /// Creates a search field.
  const LimpidSearchField({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.onCleared,
    this.autofocus = false,
    this.semanticLabel,
    this.clearTooltip = 'Effacer',
  });

  /// The controller of the field.
  final TextEditingController? controller;

  /// The placeholder text.
  final String? hint;

  /// Called whenever the value changes.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits the value.
  final ValueChanged<String>? onSubmitted;

  /// Called when the user clears the field.
  final VoidCallback? onCleared;

  /// Whether the field takes the focus on first build.
  final bool autofocus;

  /// The label announced by screen readers.
  final String? semanticLabel;

  /// The tooltip of the clear button.
  final String clearTooltip;

  @override
  State<LimpidSearchField> createState() => _LimpidSearchFieldState();
}

class _LimpidSearchFieldState extends State<LimpidSearchField> {
  late TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_handleValueChanged);
    _hasText = _controller.text.isNotEmpty;
  }

  @override
  void didUpdateWidget(LimpidSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_handleValueChanged);
      _controller = widget.controller ?? TextEditingController();
      _controller.addListener(_handleValueChanged);
      _hasText = _controller.text.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleValueChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleValueChanged() {
    final bool hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _clear() {
    _controller.clear();
    widget.onCleared?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: widget.semanticLabel,
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _hasText
              ? IconButton(
                  onPressed: _clear,
                  tooltip: widget.clearTooltip,
                  icon: const Icon(Icons.close),
                )
              : null,
        ),
      ),
    );
  }
}
