import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/features/revision/revision_models.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The card of a discussion of the manuscript.
///
/// The card shows the first message of the discussion, its replies and the
/// action that closes it. Clicking it selects the anchor of the discussion:
/// the manuscript puts the passage in relief.
class RevisionThreadCard extends StatefulWidget {
  /// Creates the card of a discussion.
  const RevisionThreadCard({
    required this.thread,
    required this.isSelected,
    required this.canResolve,
    required this.onSelect,
    required this.onResolve,
    super.key,
  });

  /// The discussion the card shows.
  final RevisionThread thread;

  /// Whether the anchor of the discussion is the selected one.
  final bool isSelected;

  /// Whether the author of the book may close the discussion.
  final bool canResolve;

  /// Called when the card is selected.
  final VoidCallback onSelect;

  /// Called when the discussion is closed.
  final VoidCallback onResolve;

  @override
  State<RevisionThreadCard> createState() => _RevisionThreadCardState();
}

class _RevisionThreadCardState extends State<RevisionThreadCard> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'revision-thread-card',
  );
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() => _isFocused = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope tokens = context.limpid;
    final RevisionComment? first = widget.thread.first;
    if (first == null) {
      return const SizedBox.shrink();
    }
    final List<RevisionComment> replies = widget.thread.replies;
    final bool isResolved = widget.thread.isResolved;
    final Color borderColor = _isFocused || widget.isSelected
        ? tokens.colors.accent
        : tokens.colors.borderSubtle;

    return Semantics(
      container: true,
      button: true,
      selected: widget.isSelected,
      label: first.authorName,
      hint: first.comment.body,
      child: Material(
        color: tokens.colors.bgSurface,
        child: InkWell(
          focusNode: _focusNode,
          onTap: widget.onSelect,
          borderRadius: BorderRadius.circular(tokens.radii.sm),
          child: Container(
            padding: EdgeInsets.all(tokens.spacing.space8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radii.sm),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LimpidCommentThread(
                  authorName: first.authorName,
                  text: first.comment.body,
                  timestamp: _timestampOf(context, first.comment.createdAt),
                  avatar: LimpidAvatar(
                    label: first.authorName,
                    size: LimpidAvatarSize.small,
                    semanticLabel: first.authorName,
                  ),
                  isResolved: isResolved,
                ),
                for (final RevisionComment reply in replies)
                  _ReplyRow(comment: reply),
                if (!isResolved) ...<Widget>[
                  SizedBox(height: tokens.spacing.space4),
                  LimpidButton(
                    label: strings.revisionResolve,
                    icon: LimpidIcons.check,
                    variant: LimpidButtonVariant.ghost,
                    size: LimpidButtonSize.small,
                    onPressed: widget.canResolve ? widget.onResolve : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The date of a message, in the format of the active locale.
String _timestampOf(BuildContext context, DateTime date) {
  return MaterialLocalizations.of(context).formatShortDate(date);
}

/// A reply of a discussion, with the role of its author.
class _ReplyRow extends StatelessWidget {
  const _ReplyRow({required this.comment});

  final RevisionComment comment;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope tokens = context.limpid;
    final ProjectRole? role = comment.role;

    return Padding(
      padding: EdgeInsets.only(
        top: tokens.spacing.space8,
        left: tokens.spacing.space12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LimpidAvatar(
            label: comment.authorName,
            size: LimpidAvatarSize.small,
            semanticLabel: comment.authorName,
          ),
          SizedBox(width: tokens.spacing.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        comment.authorName,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    if (role != null) ...<Widget>[
                      SizedBox(width: tokens.spacing.space6),
                      LimpidBadge(label: roleLabelOf(strings, role)),
                    ],
                  ],
                ),
                SizedBox(height: tokens.spacing.space4),
                Text(
                  comment.comment.body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.colors.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
