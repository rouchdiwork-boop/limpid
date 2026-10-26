import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:limpid_quill/limpid_quill.dart';

/// The panel of the assistant.
///
/// The panel offers the inline actions of `limpid_quill` — rewrite, develop,
/// shorten — and a free question. Whatever the author asks, the answer
/// arrives as a stream of fragments: they are shown as they come.
class WritingAssistantPanel extends StatefulWidget {
  /// Creates the assistant panel.
  const WritingAssistantPanel({
    required this.state,
    required this.selection,
    required this.onAction,
    required this.onSend,
    required this.onDismiss,
    super.key,
  });

  /// The state of the assistant.
  final AiPanelState state;

  /// The text the assistant works on.
  final String selection;

  /// Called with the instruction of the inline action the author picked.
  final ValueChanged<String> onAction;

  /// Called when the author sends a question.
  final ValueChanged<String> onSend;

  /// Called when the author closes the answer.
  final VoidCallback onDismiss;

  @override
  State<WritingAssistantPanel> createState() => _WritingAssistantPanelState();
}

class _WritingAssistantPanelState extends State<WritingAssistantPanel> {
  final TextEditingController _questionController = TextEditingController();

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  void _send() {
    final String question = _questionController.text.trim();
    if (question.isEmpty) {
      return;
    }
    widget.onSend(question);
    _questionController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AiPanelState state = widget.state;

    final Map<LimpidAiAction, String> instructions = <LimpidAiAction, String>{
      LimpidAiAction.rewrite: strings.editorAiRewrite,
      LimpidAiAction.expand: strings.editorAiExpand,
      LimpidAiAction.shorten: strings.editorAiShorten,
    };

    return ColoredBox(
      color: scope.colors.bgSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              scope.spacing.space16,
              scope.spacing.space12,
              scope.spacing.space8,
              scope.spacing.space12,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  LimpidIcons.suggestion,
                  size: _iconSize,
                  color: scope.colors.secondary,
                ),
                SizedBox(width: scope.spacing.space8),
                Expanded(
                  child: Text(
                    strings.editorAiTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scope.colors.fgDefault,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (state.hasAnswer || state.error != null)
                  Semantics(
                    button: true,
                    label: strings.actionCancel,
                    child: IconButton(
                      onPressed: widget.onDismiss,
                      tooltip: null,
                      icon: Icon(
                        LimpidIcons.close,
                        size: _iconSize,
                        color: scope.colors.fgMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: scope.spacing.space16),
            child: LimpidInlineAiActions(
              actions: instructions.keys.toList(growable: false),
              isLoading: state.isThinking,
              onAction: (LimpidAiAction action) {
                final String? instruction = instructions[action];
                if (instruction != null) {
                  widget.onAction(instruction);
                }
              },
            ),
          ),
          SizedBox(height: scope.spacing.space12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: scope.spacing.space16),
            child: Semantics(
              label: strings.editorSelection,
              child: Text(
                widget.selection,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
              ),
            ),
          ),
          SizedBox(height: scope.spacing.space12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: scope.spacing.space16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: LimpidTextField(
                    controller: _questionController,
                    hint: strings.editorAiPlaceholder,
                    semanticLabel: strings.editorAiPlaceholder,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                SizedBox(width: scope.spacing.space8),
                LimpidButton(
                  label: strings.editorAiSend,
                  icon: LimpidIcons.arrowRight,
                  size: LimpidButtonSize.small,
                  onPressed: state.isThinking ? null : _send,
                ),
              ],
            ),
          ),
          SizedBox(height: scope.spacing.space12),
          Expanded(child: _AnswerArea(state: state)),
        ],
      ),
    );
  }
}

/// The area showing the answer of the assistant.
class _AnswerArea extends StatelessWidget {
  const _AnswerArea({required this.state});

  final AiPanelState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    if (state.error != null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: scope.spacing.space16),
        child: LimpidBanner(
          variant: LimpidStatusVariant.danger,
          title: strings.errorGeneric,
        ),
      );
    }

    if (state.isThinking && !state.hasAnswer) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: scope.spacing.space16),
        child: Row(
          children: <Widget>[
            const LimpidSpinner(),
            SizedBox(width: scope.spacing.space8),
            Text(
              strings.editorAiThinking,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
            ),
          ],
        ),
      );
    }

    if (!state.hasAnswer) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: scope.spacing.space16),
      child: SingleChildScrollView(
        child: Text(
          state.answer,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scope.colors.fgDefault),
        ),
      ),
    );
  }
}

/// The size of the icons of the panel, in logical pixels.
const double _iconSize = 16;
