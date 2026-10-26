import 'package:flutter/material.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The rail that shows the steps of the wizard.
///
/// The current step is the only one announced as selected: the number of the
/// steps is carried by the live region of the screen.
class OnboardingStepsRail extends StatelessWidget {
  /// Creates the rail.
  const OnboardingStepsRail({
    super.key,
    required this.step,
    required this.stepCount,
    required this.labels,
  });

  /// The index of the current step.
  final int step;

  /// The number of steps of the wizard.
  final int stepCount;

  /// The name of each step.
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return ColoredBox(
      color: scope.colors.bgSurface,
      child: Padding(
        padding: EdgeInsets.all(scope.spacing.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var index = 0; index < stepCount; index++)
              Padding(
                padding: EdgeInsets.only(bottom: scope.spacing.space20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ExcludeSemantics(
                      child: Container(
                        width: scope.spacing.space24,
                        height: scope.spacing.space24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index <= step
                              ? scope.colors.accent
                              : scope.colors.bgSunken,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: index <= step
                                    ? scope.colors.fgOnAccent
                                    : scope.colors.fgSubtle,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                    SizedBox(width: scope.spacing.space12),
                    Expanded(
                      child: Semantics(
                        selected: index == step,
                        child: Text(
                          labels[index],
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: index == step
                                    ? scope.colors.fgDefault
                                    : scope.colors.fgMuted,
                                fontWeight: index == step
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The card that offers a model of book.
///
/// The card behaves like a radio button: it is focusable, it is activated by
/// the keyboard and it announces whether it is the chosen one.
class OnboardingTemplateCard extends StatelessWidget {
  /// Creates a card.
  const OnboardingTemplateCard({
    super.key,
    required this.title,
    required this.hint,
    required this.isSelected,
    required this.onTap,
  });

  /// The name of the model.
  final String title;

  /// The description of the model.
  final String hint;

  /// Whether the model is the chosen one.
  final bool isSelected;

  /// Called when the card is activated.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return Semantics(
      selected: isSelected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(scope.radii.lg),
        child: Container(
          padding: EdgeInsets.all(scope.spacing.space16),
          decoration: BoxDecoration(
            color: isSelected
                ? scope.colors.accentSubtle
                : scope.colors.bgSurface,
            borderRadius: BorderRadius.circular(scope.radii.lg),
            border: Border.all(
              color: isSelected
                  ? scope.colors.accent
                  : scope.colors.borderSubtle,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isSelected
                      ? scope.colors.accent
                      : scope.colors.fgDefault,
                ),
              ),
              SizedBox(height: scope.spacing.space6),
              Text(
                hint,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card that offers a daily rhythm.
///
/// The card behaves like a radio button: it is focusable, it is activated by
/// the keyboard and it announces whether it is the chosen one.
class OnboardingGoalCard extends StatelessWidget {
  /// Creates a card.
  const OnboardingGoalCard({
    super.key,
    required this.title,
    required this.words,
    required this.isSelected,
    required this.onTap,
  });

  /// The name of the rhythm.
  final String title;

  /// The number of words of the rhythm.
  final String words;

  /// Whether the rhythm is the chosen one.
  final bool isSelected;

  /// Called when the card is activated.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return Semantics(
      selected: isSelected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(scope.radii.md),
        child: Container(
          constraints: BoxConstraints(minHeight: scope.spacing.space48),
          padding: EdgeInsets.all(scope.spacing.space12),
          decoration: BoxDecoration(
            color: isSelected
                ? scope.colors.accentSubtle
                : scope.colors.bgSurface,
            borderRadius: BorderRadius.circular(scope.radii.md),
            border: Border.all(
              color: isSelected
                  ? scope.colors.accent
                  : scope.colors.borderSubtle,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: isSelected
                        ? scope.colors.accent
                        : scope.colors.fgDefault,
                  ),
                ),
              ),
              Text(
                words,
                style: LimpidTypography.monoStyle(color: scope.colors.fgMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
