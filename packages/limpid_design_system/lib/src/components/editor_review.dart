import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/icons/limpid_icons.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';
import 'package:limpid_design_system/src/tokens/typography.dart';

/// A thread of comments attached to a passage of the manuscript.
class LimpidCommentThread extends StatelessWidget {
  /// Creates a comment thread.
  const LimpidCommentThread({
    super.key,
    required this.authorName,
    required this.text,
    this.timestamp,
    this.onReply,
    this.replyLabel = 'Répondre',
    this.onResolve,
    this.isResolved = false,
    this.resolveLabel = 'Résoudre',
    this.avatar,
  });

  /// The name of the author of the comment.
  final String authorName;

  /// The text of the comment.
  final String text;

  /// The date of the comment.
  final String? timestamp;

  /// Called when the user replies to the comment.
  final VoidCallback? onReply;

  /// The label of the reply action.
  final String replyLabel;

  /// Called when the comment is marked as resolved.
  final VoidCallback? onResolve;

  /// Whether the comment is resolved.
  final bool isResolved;

  /// The label of the resolve action.
  final String resolveLabel;

  /// An optional avatar replacing the initials of the author.
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      child: Container(
        padding: EdgeInsets.all(tokens.spacing.space12),
        decoration: BoxDecoration(
          color: tokens.colors.bgSunken,
          borderRadius: BorderRadius.circular(tokens.radii.sm),
          border: Border.all(color: tokens.colors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (avatar != null)
                  avatar!
                else
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: tokens.colors.accentSubtle,
                    child: Text(
                      authorName.isEmpty ? '' : authorName.substring(0, 1),
                      style: textTheme.labelSmall?.copyWith(
                        color: tokens.colors.accent,
                      ),
                    ),
                  ),
                SizedBox(width: tokens.spacing.space8),
                Expanded(child: Text(authorName, style: textTheme.labelMedium)),
                if (timestamp != null)
                  Text(
                    timestamp!,
                    style: LimpidTypography.captionStyle(
                      color: tokens.colors.fgSubtle,
                    ),
                  ),
                if (isResolved)
                  Padding(
                    padding: EdgeInsets.only(left: tokens.spacing.space8),
                    child: Icon(
                      LimpidIcons.check,
                      size: 16,
                      color: tokens.colors.success,
                    ),
                  ),
              ],
            ),
            SizedBox(height: tokens.spacing.space8),
            Text(
              text,
              style: textTheme.bodyMedium?.copyWith(
                color: isResolved
                    ? tokens.colors.fgMuted
                    : tokens.colors.fgDefault,
              ),
            ),
            if (onReply != null || onResolve != null) ...<Widget>[
              SizedBox(height: tokens.spacing.space8),
              Row(
                children: <Widget>[
                  if (onReply != null)
                    TextButton(onPressed: onReply, child: Text(replyLabel)),
                  if (onResolve != null)
                    TextButton(onPressed: onResolve, child: Text(resolveLabel)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The difference between a passage and the suggestion of the assistant.
class LimpidAiSuggestionDiff extends StatelessWidget {
  /// Creates a suggestion diff.
  const LimpidAiSuggestionDiff({
    super.key,
    required this.original,
    required this.suggestion,
    this.onAccept,
    this.onReject,
    this.reason,
    this.acceptLabel = 'Accepter',
    this.rejectLabel = 'Refuser',
  });

  /// The original passage.
  final String original;

  /// The suggested passage.
  final String suggestion;

  /// Called when the suggestion is accepted.
  final VoidCallback? onAccept;

  /// Called when the suggestion is rejected.
  final VoidCallback? onReject;

  /// An optional explanation of the suggestion.
  final String? reason;

  /// The label of the accept action.
  final String acceptLabel;

  /// The label of the reject action.
  final String rejectLabel;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.colors.bgSurface,
          borderRadius: BorderRadius.circular(tokens.radii.md),
          border: Border.all(color: tokens.colors.borderSubtle),
        ),
        padding: EdgeInsets.all(tokens.spacing.space16),
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
            _DiffLine(
              text: original,
              color: tokens.colors.danger,
              background: tokens.colors.danger.withValues(alpha: 0.08),
              isRemoved: true,
            ),
            SizedBox(height: tokens.spacing.space4),
            _DiffLine(
              text: suggestion,
              color: tokens.colors.success,
              background: tokens.colors.success.withValues(alpha: 0.08),
              isRemoved: false,
            ),
            if (reason != null) ...<Widget>[
              SizedBox(height: tokens.spacing.space12),
              Text(
                reason!,
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.colors.fgMuted,
                ),
              ),
            ],
            if (onAccept != null || onReject != null) ...<Widget>[
              SizedBox(height: tokens.spacing.space12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (onReject != null)
                    TextButton(onPressed: onReject, child: Text(rejectLabel)),
                  if (onAccept != null)
                    TextButton(onPressed: onAccept, child: Text(acceptLabel)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({
    required this.text,
    required this.color,
    required this.background,
    required this.isRemoved,
  });

  final String text;
  final Color color;
  final Color background;
  final bool isRemoved;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: isRemoved ? '− ' : '+ ',
              style: textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: text,
              style: textTheme.bodyMedium?.copyWith(
                color: color,
                decoration: isRemoved ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The synchronization status of a document.
enum LimpidSyncStatus {
  /// The document is saved on the server.
  synced,

  /// The document is being synchronized.
  syncing,

  /// The device is offline.
  offline,

  /// The synchronization failed.
  error,
}

/// The pill displaying the synchronization status of a document.
class LimpidSyncStatusPill extends StatelessWidget {
  /// Creates a synchronization status pill.
  const LimpidSyncStatusPill({super.key, required this.status, this.label});

  /// The status of the document.
  final LimpidSyncStatus status;

  /// The label of the status. Defaults to the label of the status.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final (Color color, IconData icon, String fallback) = switch (status) {
      LimpidSyncStatus.synced => (
        tokens.colors.success,
        LimpidIcons.check,
        'Synchronisé',
      ),
      LimpidSyncStatus.syncing => (
        tokens.colors.info,
        LimpidIcons.sync,
        'Synchronisation',
      ),
      LimpidSyncStatus.offline => (
        tokens.colors.fgMuted,
        LimpidIcons.offline,
        'Hors ligne',
      ),
      LimpidSyncStatus.error => (
        tokens.colors.danger,
        LimpidIcons.error,
        'Erreur',
      ),
    };

    return Semantics(
      label: label ?? fallback,
      liveRegion: status == LimpidSyncStatus.syncing,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.space8,
          vertical: tokens.spacing.space4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(tokens.radii.pill),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            SizedBox(width: tokens.spacing.space6),
            Text(
              label ?? fallback,
              style: textTheme.labelMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
