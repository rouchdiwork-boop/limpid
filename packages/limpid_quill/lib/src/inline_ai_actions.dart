import 'package:flutter/material.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'accessibility.dart';
import 'word_diff.dart';

/// The AI actions offered on a selection.
enum LimpidAiAction {
  /// Rewrites the selection.
  rewrite,

  /// Develops the selection.
  expand,

  /// Shortens the selection.
  shorten,

  /// Simplifies the wording of the selection.
  simplify,

  /// Changes the tone of the selection.
  changeTone,

  /// Translates the selection.
  translate,
}

/// The label of an AI action, as shown to the author.
String aiActionLabel(LimpidAiAction action) => switch (action) {
  LimpidAiAction.rewrite => 'Réécrire',
  LimpidAiAction.expand => 'Étendre',
  LimpidAiAction.shorten => 'Raccourcir',
  LimpidAiAction.simplify => 'Simplifier',
  LimpidAiAction.changeTone => 'Changer le ton',
  LimpidAiAction.translate => 'Traduire',
};

/// The AI actions proposed by default, in the order they are shown.
const List<LimpidAiAction> kDefaultAiActions = <LimpidAiAction>[
  LimpidAiAction.rewrite,
  LimpidAiAction.expand,
  LimpidAiAction.shorten,
  LimpidAiAction.simplify,
  LimpidAiAction.changeTone,
  LimpidAiAction.translate,
];

/// A suggestion produced by the assistant.
///
/// The package never calls the network: the suggestion is built by the
/// application and handed over to the widget.
@immutable
class LimpidAiSuggestion {
  /// Creates a suggestion.
  const LimpidAiSuggestion({
    required this.original,
    required this.suggestion,
    this.reason,
  });

  /// The passage the suggestion replaces.
  final String original;

  /// The passage the assistant proposes.
  final String suggestion;

  /// An optional explanation of the suggestion.
  final String? reason;

  /// The difference between the original passage and the suggestion.
  List<LimpidDiffSegment> get diff => diffWords(original, suggestion);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LimpidAiSuggestion &&
          other.original == original &&
          other.suggestion == suggestion &&
          other.reason == reason);

  @override
  int get hashCode => Object.hash(original, suggestion, reason);
}

/// The bar of AI actions shown above a selection.
///
/// The bar offers the six actions of the assistant; once a suggestion comes
/// back, it is presented as a difference — the additions underlined in the
/// success colour, the deletions struck through in the danger colour — and
/// three actions become available: apply, ignore and regenerate.
class LimpidInlineAiActions extends StatelessWidget {
  /// Creates the bar of AI actions.
  const LimpidInlineAiActions({
    super.key,
    required this.onAction,
    this.suggestion,
    this.onApply,
    this.onDismiss,
    this.onRegenerate,
    this.isLoading = false,
    this.actions = kDefaultAiActions,
  });

  /// Called when the author picks an action.
  final ValueChanged<LimpidAiAction> onAction;

  /// The suggestion to present, `null` when there is none.
  final LimpidAiSuggestion? suggestion;

  /// Called when the author applies the suggestion.
  final VoidCallback? onApply;

  /// Called when the author ignores the suggestion.
  final VoidCallback? onDismiss;

  /// Called when the author asks for another suggestion.
  final VoidCallback? onRegenerate;

  /// Whether the assistant is working.
  final bool isLoading;

  /// The actions proposed by the bar.
  final List<LimpidAiAction> actions;

  @override
  Widget build(BuildContext context) {
    final LimpidAiSuggestion? current = suggestion;
    if (current == null) {
      return _buildActions(context);
    }
    return _buildSuggestion(context, current);
  }

  Widget _buildActions(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      label: 'Actions de l’assistant',
      child: Container(
        padding: EdgeInsets.all(tokens.spacing.space8),
        decoration: BoxDecoration(
          color: tokens.colors.bgRaised,
          borderRadius: BorderRadius.circular(tokens.radii.md),
          border: Border.all(color: tokens.colors.borderDefault),
        ),
        child: Wrap(
          spacing: tokens.spacing.space4,
          runSpacing: tokens.spacing.space4,
          children: <Widget>[
            for (final LimpidAiAction action in actions)
              Semantics(
                button: true,
                enabled: !isLoading,
                label: aiActionLabel(action),
                child: TextButton(
                  onPressed: isLoading ? null : () => onAction(action),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.colors.secondary,
                    minimumSize: const Size(
                      kMinimumTapTarget,
                      kMinimumTapTarget,
                    ),
                    textStyle: textTheme.labelMedium,
                  ),
                  child: Text(aiActionLabel(action)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestion(BuildContext context, LimpidAiSuggestion suggestion) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      label: 'Suggestion de l’assistant',
      child: Container(
        padding: EdgeInsets.all(tokens.spacing.space16),
        decoration: BoxDecoration(
          color: tokens.colors.bgSurface,
          borderRadius: BorderRadius.circular(tokens.radii.md),
          border: Border.all(color: tokens.colors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  LimpidIcons.suggestion,
                  size: 16,
                  color: tokens.colors.secondary,
                ),
                SizedBox(width: tokens.spacing.space8),
                Expanded(
                  child: Text(
                    'Suggestion',
                    style: textTheme.labelMedium?.copyWith(
                      color: tokens.colors.secondary,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.space12),
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  for (final LimpidDiffSegment segment in suggestion.diff)
                    TextSpan(
                      text: segment.text,
                      style: _diffStyle(segment.kind, tokens.colors),
                    ),
                ],
              ),
              style: textTheme.bodyMedium,
            ),
            if (suggestion.reason != null) ...<Widget>[
              SizedBox(height: tokens.spacing.space12),
              Text(
                suggestion.reason!,
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.colors.fgMuted,
                ),
              ),
            ],
            SizedBox(height: tokens.spacing.space12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (onDismiss != null)
                  Semantics(
                    button: true,
                    label: 'Ignorer la suggestion',
                    child: TextButton(
                      onPressed: onDismiss,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          kMinimumTapTarget,
                          kMinimumTapTarget,
                        ),
                      ),
                      child: const Text('Ignorer'),
                    ),
                  ),
                if (onRegenerate != null)
                  Semantics(
                    button: true,
                    label: 'Régénérer la suggestion',
                    child: TextButton(
                      onPressed: onRegenerate,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          kMinimumTapTarget,
                          kMinimumTapTarget,
                        ),
                      ),
                      child: const Text('Régénérer'),
                    ),
                  ),
                if (onApply != null)
                  Semantics(
                    button: true,
                    label: 'Appliquer la suggestion',
                    child: TextButton(
                      onPressed: onApply,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          kMinimumTapTarget,
                          kMinimumTapTarget,
                        ),
                      ),
                      child: const Text('Appliquer'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TextStyle? _diffStyle(LimpidDiffKind kind, LimpidColors colors) {
    return switch (kind) {
      LimpidDiffKind.unchanged => null,
      LimpidDiffKind.insertion => TextStyle(
        color: colors.success,
        decoration: TextDecoration.underline,
      ),
      LimpidDiffKind.deletion => TextStyle(
        color: colors.danger,
        decoration: TextDecoration.lineThrough,
      ),
    };
  }
}
