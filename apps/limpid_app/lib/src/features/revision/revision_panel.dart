import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_app/src/features/revision/presence_bar.dart';
import 'package:limpid_app/src/features/revision/presence_models.dart';
import 'package:limpid_app/src/features/revision/revision_models.dart';
import 'package:limpid_app/src/features/revision/revision_providers.dart';
import 'package:limpid_app/src/features/revision/revision_thread_card.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The thickness of the hairline separating two zones of the panel.
const double _kHairline = 1;

/// The panel of the review: the comments anchored on the manuscript, grouped
/// by discussion.
///
/// The panel shows the open discussions of the scene being read, the
/// collaborators and the role each of them holds. A discussion that is closed
/// leaves the open list and joins the closed ones, which stay folded until
/// the author asks for them.
class RevisionPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const RevisionPanel({
    required this.projectId,
    required this.threads,
    required this.members,
    required this.currentAuthorId,
    this.peers = const <PresencePeerView>[],
    super.key,
  });

  /// The project being reviewed.
  final String projectId;

  /// The discussions anchored on the manuscript being read.
  final List<RevisionThread> threads;

  /// The collaborators of the project, with the role they hold.
  final List<ProjectMember> members;

  /// The account of the author of the book.
  final AuthorId currentAuthorId;

  /// The peers present on the manuscript being read.
  ///
  /// The relay owns the presence: the panel only displays the peers it was
  /// given, and shows nothing when the author writes alone.
  final List<PresencePeerView> peers;

  @override
  ConsumerState<RevisionPanel> createState() => _RevisionPanelState();
}

class _RevisionPanelState extends ConsumerState<RevisionPanel> {
  bool _areClosedThreadsVisible = false;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final RevisionSelection selection = ref.watch(
      revisionSelectionProvider(widget.projectId),
    );
    final RevisionState actions = ref.watch(
      revisionControllerProvider(widget.projectId),
    );
    _listenToTheFailure();

    final List<RevisionThread> open = widget.threads
        .where((RevisionThread thread) => !thread.isResolved)
        .toList(growable: false);
    final List<RevisionThread> closed = widget.threads
        .where((RevisionThread thread) => thread.isResolved)
        .toList(growable: false);
    final bool canResolve =
        actions.canAct && _canResolve(widget.members, widget.currentAuthorId);

    return ColoredBox(
      color: tokens.colors.bgSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PanelHeader(openCount: open.length),
          PresenceBar(
            peers: widget.peers,
            label: AppLocalizations.of(context).revisionMembers,
          ),
          _MembersRow(members: widget.members),
          Divider(
            height: _kHairline,
            thickness: _kHairline,
            color: tokens.colors.borderSubtle,
          ),
          Expanded(
            child: _buildList(
              context: context,
              open: open,
              closed: closed,
              canResolve: canResolve,
              selection: selection,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the list of the discussions of the manuscript.
  Widget _buildList({
    required BuildContext context,
    required List<RevisionThread> open,
    required List<RevisionThread> closed,
    required bool canResolve,
    required RevisionSelection selection,
  }) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope tokens = context.limpid;

    if (widget.threads.isEmpty) {
      return LimpidEmptyState(
        title: strings.revisionEmptyMessage,
        icon: LimpidIcons.comment,
      );
    }

    return ListView(
      padding: EdgeInsets.all(tokens.spacing.space12),
      children: <Widget>[
        for (final RevisionThread thread in open) ...<Widget>[
          _cardOf(thread, canResolve, selection),
          SizedBox(height: tokens.spacing.space8),
        ],
        if (closed.isNotEmpty) ...<Widget>[
          _ClosedSection(
            count: closed.length,
            isExpanded: _areClosedThreadsVisible,
            onToggle: _toggleClosedThreads,
          ),
          if (_areClosedThreadsVisible) ...<Widget>[
            SizedBox(height: tokens.spacing.space8),
            for (final RevisionThread thread in closed) ...<Widget>[
              _cardOf(thread, canResolve, selection),
              SizedBox(height: tokens.spacing.space8),
            ],
          ],
        ],
      ],
    );
  }

  /// Builds the card of a discussion.
  Widget _cardOf(
    RevisionThread thread,
    bool canResolve,
    RevisionSelection selection,
  ) {
    final RevisionAnchor? anchor = thread.anchor;
    return RevisionThreadCard(
      thread: thread,
      isSelected: anchor != null && selection.isSelected(anchor.markId.value),
      canResolve: canResolve,
      onSelect: () => _select(anchor),
      onResolve: () => unawaited(
        ref
            .read(revisionControllerProvider(widget.projectId).notifier)
            .resolve(thread.thread),
      ),
      onReopen: () => unawaited(
        ref
            .read(revisionControllerProvider(widget.projectId).notifier)
            .reopen(thread.thread),
      ),
      onReply: (String body) => ref
          .read(revisionControllerProvider(widget.projectId).notifier)
          .reply(
            thread: thread.thread,
            body: body,
            author: widget.currentAuthorId,
          ),
    );
  }

  /// Selects the anchor of a discussion in the manuscript.
  void _select(RevisionAnchor? anchor) {
    if (anchor == null) {
      return;
    }
    ref
        .read(revisionSelectionProvider(widget.projectId).notifier)
        .select(
          anchorId: anchor.markId.value,
          threadId: anchor.thread.id.value,
        );
  }

  /// Shows the failure of an action of the panel.
  ///
  /// The controller keeps the error until somebody reads it. The panel is
  /// that reader: without it, a refused write would leave the author with a
  /// button that does nothing.
  void _listenToTheFailure() {
    ref.listen<RevisionState>(revisionControllerProvider(widget.projectId), (
      RevisionState? previous,
      RevisionState next,
    ) {
      final Object? error = next.error;
      if (error == null || previous?.error == error) {
        return;
      }
      _showFailure(error);
      ref
          .read(revisionControllerProvider(widget.projectId).notifier)
          .clearError();
    });
  }

  /// Tells the author that the action failed.
  void _showFailure(Object error) {
    if (!mounted) {
      return;
    }
    final AppLocalizations strings = AppLocalizations.of(context);
    final String message = error is ApiException
        ? error.message
        : strings.revisionActionFailed;
    LimpidSnackbar.show(
      context,
      message: message,
      variant: LimpidStatusVariant.danger,
    );
  }

  /// Folds or unfolds the closed discussions.
  void _toggleClosedThreads() {
    setState(() => _areClosedThreadsVisible = !_areClosedThreadsVisible);
  }

  /// Whether the author of the book may close the discussions.
  bool _canResolve(List<ProjectMember> members, AuthorId authorId) {
    for (final ProjectMember member in members) {
      if (member.id == authorId) {
        return canEditManuscript(member.role);
      }
    }
    return false;
  }
}

/// The header of the panel: the title of the review and the number of open
/// discussions.
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.openCount});

  final int openCount;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope tokens = context.limpid;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.space16,
        tokens.spacing.space12,
        tokens.spacing.space16,
        tokens.spacing.space8,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            LimpidIcons.comment,
            size: _kIconSize,
            color: tokens.colors.secondary,
          ),
          SizedBox(width: tokens.spacing.space8),
          Expanded(
            child: Text(
              strings.revisionTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: tokens.colors.fgDefault,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          LimpidBadge(
            label: '$openCount',
            icon: LimpidIcons.comment,
            variant: LimpidStatusVariant.info,
          ),
        ],
      ),
    );
  }
}

/// The row of the collaborators, with the role each of them holds.
class _MembersRow extends StatelessWidget {
  const _MembersRow({required this.members});

  final List<ProjectMember> members;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope tokens = context.limpid;

    if (members.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: tokens.spacing.space40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.space16),
        children: <Widget>[
          for (final ProjectMember member in members)
            Padding(
              padding: EdgeInsets.only(right: tokens.spacing.space12),
              child: Row(
                children: <Widget>[
                  LimpidAvatar(
                    label: member.displayName,
                    size: LimpidAvatarSize.small,
                    semanticLabel: member.displayName,
                  ),
                  SizedBox(width: tokens.spacing.space6),
                  LimpidBadge(label: roleLabelOf(strings, member.role)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The folded list of the closed discussions.
class _ClosedSection extends StatelessWidget {
  const _ClosedSection({
    required this.count,
    required this.isExpanded,
    required this.onToggle,
  });

  final int count;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope tokens = context.limpid;

    return Row(
      children: <Widget>[
        LimpidChip(
          label: strings.revisionResolved,
          icon: LimpidIcons.check,
          isSelected: isExpanded,
          semanticLabel: strings.revisionResolved,
          onTap: onToggle,
        ),
        SizedBox(width: tokens.spacing.space6),
        LimpidBadge(label: '$count', variant: LimpidStatusVariant.success),
      ],
    );
  }
}

/// The size of the icons of the panel, in logical pixels.
const double _kIconSize = 16;
