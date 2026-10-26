import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/icons/limpid_icons.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';

/// A step of a [LimpidStepper].
@immutable
class LimpidStepperStep {
  /// Creates a step.
  const LimpidStepperStep({
    required this.label,
    this.description,
    this.isComplete = false,
  });

  /// The label of the step.
  final String label;

  /// An optional secondary line.
  final String? description;

  /// Whether the step has already been completed.
  final bool isComplete;
}

/// The stepper of the Limpid design system.
///
/// It displays an ordered progression: the current step is highlighted, the
/// completed ones carry a check icon.
class LimpidStepper extends StatelessWidget {
  /// Creates a stepper.
  const LimpidStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  /// The steps of the progression.
  final List<LimpidStepperStep> steps;

  /// The index of the current step.
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int index = 0; index < steps.length; index++) ...<Widget>[
            if (index > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: EdgeInsets.symmetric(
                    horizontal: tokens.spacing.space8,
                  ),
                  color: index <= currentIndex
                      ? tokens.colors.accent
                      : tokens.colors.borderSubtle,
                ),
              ),
            _LimpidStepperItem(
              index: index,
              step: steps[index],
              isCurrent: index == currentIndex,
              isComplete: steps[index].isComplete || index < currentIndex,
              labelStyle: textTheme.labelMedium,
              descriptionStyle: textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _LimpidStepperItem extends StatelessWidget {
  const _LimpidStepperItem({
    required this.index,
    required this.step,
    required this.isCurrent,
    required this.isComplete,
    required this.labelStyle,
    required this.descriptionStyle,
  });

  final int index;
  final LimpidStepperStep step;
  final bool isCurrent;
  final bool isComplete;
  final TextStyle? labelStyle;
  final TextStyle? descriptionStyle;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;

    final Color tone = isCurrent
        ? tokens.colors.accent
        : isComplete
        ? tokens.colors.success
        : tokens.colors.fgSubtle;

    return Semantics(
      label: step.label,
      selected: isCurrent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrent
                  ? tokens.colors.accentSubtle
                  : isComplete
                  ? tokens.colors.success.withValues(alpha: 0.12)
                  : tokens.colors.bgSunken,
              shape: BoxShape.circle,
              border: Border.all(color: tone, width: isCurrent ? 2 : 1),
            ),
            child: isComplete
                ? Icon(LimpidIcons.check, size: 16, color: tone)
                : Text(
                    '${index + 1}',
                    style: labelStyle?.copyWith(color: tone),
                  ),
          ),
          SizedBox(height: tokens.spacing.space8),
          Text(
            step.label,
            textAlign: TextAlign.center,
            style: labelStyle?.copyWith(
              color: isCurrent
                  ? tokens.colors.fgDefault
                  : tokens.colors.fgMuted,
            ),
          ),
          if (step.description != null) ...<Widget>[
            SizedBox(height: tokens.spacing.space2),
            Text(
              step.description!,
              textAlign: TextAlign.center,
              style: descriptionStyle?.copyWith(color: tokens.colors.fgSubtle),
            ),
          ],
        ],
      ),
    );
  }
}
