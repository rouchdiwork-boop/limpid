import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';

/// The checkbox of the Limpid design system.
///
/// The whole row is clickable and keeps a 48 pixel high hit area.
class LimpidCheckbox extends StatelessWidget {
  /// Creates a checkbox.
  const LimpidCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.tristate = false,
    this.semanticLabel,
  });

  /// The current value.
  final bool? value;

  /// Called when the value changes. A null callback makes it read only.
  final ValueChanged<bool?>? onChanged;

  /// The label displayed next to the box.
  final String? label;

  /// A secondary line displayed under the label.
  final String? description;

  /// Whether the checkbox cycles through a third, mixed state.
  final bool tristate;

  /// The label announced by screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? label,
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        tristate: tristate,
        title: label == null ? null : Text(label!),
        subtitle: description == null ? null : Text(description!),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: false,
      ),
    );
  }
}

/// A radio button of the Limpid design system.
///
/// The radio manages its own [RadioGroup] when it is not already placed
/// inside a [LimpidRadioGroup], so it can be used on its own.
class LimpidRadio<T> extends StatelessWidget {
  /// Creates a radio button.
  const LimpidRadio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.label,
    this.description,
    this.semanticLabel,
  });

  /// The value carried by this radio button.
  final T value;

  /// The value currently selected in the group.
  final T? groupValue;

  /// Called when the radio button is picked.
  final ValueChanged<T?> onChanged;

  /// The label displayed next to the radio button.
  final String? label;

  /// A secondary line displayed under the label.
  final String? description;

  /// The label announced by screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget tile = RadioListTile<T>(
      value: value,
      title: label == null ? null : Text(label!),
      subtitle: description == null ? null : Text(description!),
      contentPadding: EdgeInsets.zero,
      dense: false,
    );

    final Widget content = Semantics(
      label: semanticLabel ?? label,
      child: tile,
    );

    if (RadioGroup.maybeOf<T>(context) != null) {
      return content;
    }

    return RadioGroup<T>(
      groupValue: groupValue,
      onChanged: onChanged,
      child: content,
    );
  }
}

/// A group of radio buttons of the Limpid design system.
///
/// It gives the arrow key navigation of the platform to the radios it
/// contains.
class LimpidRadioGroup<T> extends StatelessWidget {
  /// Creates a radio group.
  const LimpidRadioGroup({
    super.key,
    required this.groupValue,
    required this.onChanged,
    required this.child,
  });

  /// The value currently selected in the group.
  final T? groupValue;

  /// Called when the selection changes.
  final ValueChanged<T?> onChanged;

  /// The radios of the group.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<T>(
      groupValue: groupValue,
      onChanged: onChanged,
      child: child,
    );
  }
}

/// The switch of the Limpid design system.
class LimpidSwitch extends StatelessWidget {
  /// Creates a switch.
  const LimpidSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.semanticLabel,
  });

  /// The current value.
  final bool value;

  /// Called when the value changes. A null callback makes it read only.
  final ValueChanged<bool>? onChanged;

  /// The label displayed next to the switch.
  final String? label;

  /// A secondary line displayed under the label.
  final String? description;

  /// The label announced by screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? label,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: label == null ? null : Text(label!),
        subtitle: description == null ? null : Text(description!),
        contentPadding: EdgeInsets.zero,
        dense: false,
      ),
    );
  }
}

/// The slider of the Limpid design system.
class LimpidSlider extends StatelessWidget {
  /// Creates a slider.
  const LimpidSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.valueLabel,
    this.semanticLabel,
  });

  /// The current value.
  final double value;

  /// Called when the value changes.
  final ValueChanged<double>? onChanged;

  /// The lowest selectable value.
  final double min;

  /// The highest selectable value.
  final double max;

  /// The number of discrete steps, when the slider is discrete.
  final int? divisions;

  /// The label displayed above the slider.
  final String? label;

  /// The current value, displayed above the slider.
  final String? valueLabel;

  /// The label announced by screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: semanticLabel ?? label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (label != null || valueLabel != null)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.space4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  if (label != null) Text(label!, style: textTheme.labelMedium),
                  if (valueLabel != null)
                    Text(
                      valueLabel!,
                      style: textTheme.labelMedium?.copyWith(
                        color: tokens.colors.fgMuted,
                      ),
                    ),
                ],
              ),
            ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
