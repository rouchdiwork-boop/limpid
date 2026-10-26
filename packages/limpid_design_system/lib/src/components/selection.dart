import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';

/// An entry of a [LimpidSelect] or of a [LimpidCombobox].
@immutable
class LimpidSelectItem<T> {
  /// Creates a selectable item.
  const LimpidSelectItem({
    required this.value,
    required this.label,
    this.icon,
    this.isEnabled = true,
  });

  /// The value carried by the item.
  final T value;

  /// The label displayed to the user.
  final String label;

  /// An optional leading icon.
  final IconData? icon;

  /// Whether the item can be picked.
  final bool isEnabled;

  @override
  String toString() => 'LimpidSelectItem($label)';
}

/// The dropdown select of the Limpid design system.
///
/// It is a controlled component: the caller owns the selected value and
/// receives every change through [onChanged].
class LimpidSelect<T> extends StatelessWidget {
  /// Creates a select.
  const LimpidSelect({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.semanticLabel,
  });

  /// The available items.
  final List<LimpidSelectItem<T>> items;

  /// The currently selected value.
  final T? value;

  /// Called when the selection changes.
  final ValueChanged<T?>? onChanged;

  /// The floating label of the select.
  final String? label;

  /// The placeholder text.
  final String? hint;

  /// The helper text displayed below the select.
  final String? helperText;

  /// The error text.
  final String? errorText;

  /// Whether the select accepts input.
  final bool enabled;

  /// The label announced by screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: semanticLabel ?? label,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          errorText: errorText,
        ),
        isEmpty: value == null,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isDense: true,
            isExpanded: true,
            borderRadius: BorderRadius.circular(tokens.radii.md),
            dropdownColor: tokens.colors.bgRaised,
            style: textTheme.bodyMedium,
            icon: Icon(Icons.expand_more, color: tokens.colors.fgMuted),
            hint: hint == null
                ? null
                : Text(
                    hint!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.colors.fgSubtle,
                    ),
                  ),
            onChanged: enabled ? onChanged : null,
            items: items
                .map(
                  (LimpidSelectItem<T> item) => DropdownMenuItem<T>(
                    value: item.value,
                    enabled: item.isEnabled,
                    child: Row(
                      children: <Widget>[
                        if (item.icon != null) ...<Widget>[
                          Icon(item.icon, size: 18),
                          SizedBox(width: tokens.spacing.space8),
                        ],
                        Flexible(
                          child: Text(
                            item.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

/// A segment of a [LimpidSegmentedControl].
@immutable
class LimpidSegment<T> {
  /// Creates a segment.
  const LimpidSegment({
    required this.value,
    required this.label,
    this.icon,
    this.isEnabled = true,
  });

  /// The value carried by the segment.
  final T value;

  /// The label of the segment.
  final String label;

  /// An optional icon.
  final IconData? icon;

  /// Whether the segment can be selected.
  final bool isEnabled;
}

/// The segmented control of the Limpid design system.
class LimpidSegmentedControl<T> extends StatelessWidget {
  /// Creates a segmented control.
  const LimpidSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.multiSelect = false,
    this.semanticLabel,
  });

  /// The available segments.
  final List<LimpidSegment<T>> segments;

  /// The selected value, or the selected values in multi select mode.
  final Set<T> selected;

  /// Called when the selection changes.
  final ValueChanged<Set<T>> onSelectionChanged;

  /// Whether several segments can be selected at once.
  final bool multiSelect;

  /// The label announced by screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      container: true,
      child: SegmentedButton<T>(
        segments: segments
            .map(
              (LimpidSegment<T> segment) => ButtonSegment<T>(
                value: segment.value,
                enabled: segment.isEnabled,
                label: Text(segment.label),
                icon: segment.icon == null ? null : Icon(segment.icon),
              ),
            )
            .toList(growable: false),
        selected: selected,
        showSelectedIcon: false,
        emptySelectionAllowed: true,
        multiSelectionEnabled: multiSelect,
        onSelectionChanged: onSelectionChanged,
      ),
    );
  }
}
