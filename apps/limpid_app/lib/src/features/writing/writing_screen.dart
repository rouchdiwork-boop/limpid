import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_app/src/editor/editor_controller.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_app/src/editor/editor_providers.dart';
import 'package:limpid_app/src/editor/editor_statistics.dart';
import 'package:limpid_app/src/features/revision/revision_anchors.dart';
import 'package:limpid_app/src/features/revision/revision_models.dart';
import 'package:limpid_app/src/features/revision/revision_panel.dart';
import 'package:limpid_app/src/features/revision/revision_providers.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_assistant_panel.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_manuscript_pane.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_offline_banner.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_outline_panel.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_status_bar.dart';
import 'package:limpid_app/src/features/writing/widgets/writing_toolbar.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_quill/limpid_quill.dart'
    show LimpidCommentAnchor, SceneBlock;

/// The width of the plan, in logical pixels.
const double _kPlanWidth = 268;

/// The width of the assistant panel, in logical pixels.
const double _kAssistantWidth = 320;

/// The width of the review panel, in logical pixels.
const double _kRevisionWidth = 320;

/// The height of the review panel when it lies under the manuscript.
const double _kRevisionHeight = 280;

/// The width above which the plan is shown next to the manuscript.
const double _kWideBreakpoint = 860;

/// The width above which the assistant is shown next to the manuscript.
const double _kRoomyBreakpoint = 1180;

/// The thickness of the hairline separating two panels.
const double _kHairline = 1;

/// The writing surface of a project.
///
/// The screen holds the three pieces of the studio of an author: the plan of
/// the book, the manuscript being written and the assistant. Everything it
/// shows comes from the repositories — the plan from the chapters and the
/// scenes, the text from the CRDT document of the scene, the counters from
/// the text itself. The panel of the review holds the comments anchored on
/// the manuscript: it lies next to the manuscript on the wide screens, and
/// under it on the narrow ones.
class WritingScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const WritingScreen({required this.projectId, super.key});

  /// The identifier of the project.
  final String projectId;

  @override
  ConsumerState<WritingScreen> createState() => _WritingScreenState();
}

class _WritingScreenState extends ConsumerState<WritingScreen> {
  bool _isPlanVisible = false;
  bool _isAssistantVisible = false;
  bool _isRevisionVisible = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<WritingOutline> outline = ref.watch(
      writingOutlineProvider(widget.projectId),
    );
    final WritingState state = ref.watch(
      writingControllerProvider(widget.projectId),
    );
    final AsyncValue<SyncStatus> sync = ref.watch(syncStatusProvider);
    final AuthorId authorId = ref.watch(authorIdProvider);
    final AsyncValue<List<CommentThread>> threads = ref.watch(
      revisionThreadsProvider(widget.projectId),
    );
    final AsyncValue<List<ProjectMember>> members = ref.watch(
      revisionMembersProvider(widget.projectId),
    );
    final RevisionSelection selection = ref.watch(
      revisionSelectionProvider(widget.projectId),
    );

    _forgetTheSelectionOnAnotherScene();

    final List<ProjectMember> collaborators =
        members.value ?? const <ProjectMember>[];
    final List<RevisionThread> revisionThreads = _revisionThreadsOf(
      state: state,
      threads: threads.value ?? const <CommentThread>[],
      members: collaborators,
    );
    final List<LimpidCommentAnchor> anchors = editorAnchorsOf(revisionThreads);

    return Scaffold(
      body: Column(
        children: <Widget>[
          WritingToolbar(
            syncStatus: sync.value,
            isReadMode: state.isReadMode,
            isAssistantVisible: _isAssistantVisible,
            isRevisionVisible: _isRevisionVisible,
            onTogglePlan: () =>
                setState(() => _isPlanVisible = !_isPlanVisible),
            onToggleAssistant: () =>
                setState(() => _isAssistantVisible = !_isAssistantVisible),
            onToggleRevision: () =>
                setState(() => _isRevisionVisible = !_isRevisionVisible),
            onToggleReadMode: () => ref
                .read(writingControllerProvider(widget.projectId).notifier)
                .toggleReadMode(),
          ),
          if (sync.value == SyncStatus.offline) const WritingOfflineBanner(),
          Expanded(
            child: _buildWorkspace(
              context: context,
              outline: outline,
              state: state,
              authorId: authorId,
              revisionThreads: revisionThreads,
              collaborators: collaborators,
              anchors: anchors,
              selection: selection,
            ),
          ),
          WritingStatusBar(
            wordCount: state.wordCount,
            readingMinutes: readingMinutesOf(state.wordCount),
            saveState: state.saveState,
          ),
        ],
      ),
    );
  }

  /// Builds the workspace: the plan, the manuscript, the review and the
  /// assistant.
  Widget _buildWorkspace({
    required BuildContext context,
    required AsyncValue<WritingOutline> outline,
    required WritingState state,
    required AuthorId authorId,
    required List<RevisionThread> revisionThreads,
    required List<ProjectMember> collaborators,
    required List<LimpidCommentAnchor> anchors,
    required RevisionSelection selection,
  }) {
    final WritingController controller = ref.read(
      writingControllerProvider(widget.projectId).notifier,
    );

    final Widget plan = WritingOutlinePanel(
      outline: outline.value ?? WritingOutline.empty,
      activeSceneId: state.activeScene?.id,
      onSelectScene: (OutlineScene scene) =>
          unawaited(controller.selectScene(scene)),
    );

    final Widget manuscript = WritingManuscriptPane(
      scene: state.activeScene,
      authorId: authorId,
      blocks: state.document == null
          ? const <SceneBlock>[]
          : sceneBlocksOf(state.document!),
      isDocumentLoading: state.document == null,
      lamport: state.lamport,
      isReadMode: state.isReadMode,
      commentAnchors: anchors,
      selectedAnchor: _selectedAnchorOf(anchors, selection),
      onSelectAnchor: _selectAnchor,
      onClearSelection: _clearSelection,
      onChanged: (List<SyncOp> operations) =>
          unawaited(controller.applyOperations(operations)),
    );

    final Widget assistant = WritingAssistantPanel(
      state: state.ai,
      selection: state.selection,
      onAction: (String instruction) =>
          unawaited(controller.askAssistant(instruction)),
      onSend: (String question) => unawaited(controller.askAssistant(question)),
      onDismiss: controller.dismissAssistant,
    );

    final Widget revision = RevisionPanel(
      projectId: widget.projectId,
      threads: revisionThreads,
      members: collaborators,
      currentAuthorId: authorId,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth >= _kWideBreakpoint;
        final bool isRoomy = constraints.maxWidth >= _kRoomyBreakpoint;
        final bool showPlan = isWide || _isPlanVisible;
        final bool showAssistant = _isAssistantVisible;
        final bool showRevision = _isRevisionVisible;

        final Widget manuscriptArea = showRevision && !isRoomy
            ? Column(
                children: <Widget>[
                  Expanded(child: manuscript),
                  SizedBox(height: _kRevisionHeight, child: revision),
                ],
              )
            : manuscript;

        return Stack(
          children: <Widget>[
            Row(
              children: <Widget>[
                if (isWide) ...<Widget>[
                  SizedBox(width: _kPlanWidth, child: plan),
                  const VerticalDivider(width: _kHairline),
                ],
                Expanded(child: manuscriptArea),
                if (showRevision && isRoomy) ...<Widget>[
                  const VerticalDivider(width: _kHairline),
                  SizedBox(width: _kRevisionWidth, child: revision),
                ],
                if (isRoomy && showAssistant) ...<Widget>[
                  const VerticalDivider(width: _kHairline),
                  SizedBox(width: _kAssistantWidth, child: assistant),
                ],
              ],
            ),
            if (!isWide && showPlan)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _kPlanWidth,
                child: plan,
              ),
            if (!isRoomy && showAssistant)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: _kAssistantWidth,
                child: assistant,
              ),
          ],
        );
      },
    );
  }

  /// The discussions anchored on the manuscript being read.
  List<RevisionThread> _revisionThreadsOf({
    required WritingState state,
    required List<CommentThread> threads,
    required List<ProjectMember> members,
  }) {
    final CrdtDocument? document = state.document;
    if (document == null) {
      return const <RevisionThread>[];
    }
    return revisionThreadsOf(
      anchors: revisionAnchorsOf(document: document, threads: threads),
      members: members,
    );
  }

  /// The anchor the author selected, `null` when nothing is selected.
  LimpidCommentAnchor? _selectedAnchorOf(
    List<LimpidCommentAnchor> anchors,
    RevisionSelection selection,
  ) {
    for (final LimpidCommentAnchor anchor in anchors) {
      if (anchor.id == selection.anchorId) {
        return anchor;
      }
    }
    return null;
  }

  /// Selects an anchor of the manuscript.
  void _selectAnchor(LimpidCommentAnchor anchor) {
    ref
        .read(revisionSelectionProvider(widget.projectId).notifier)
        .select(anchorId: anchor.id);
  }

  /// Drops the selection.
  void _clearSelection() {
    ref.read(revisionSelectionProvider(widget.projectId).notifier).clear();
  }

  /// Forgets the selection when the author reads another scene.
  void _forgetTheSelectionOnAnotherScene() {
    ref.listen<WritingState>(writingControllerProvider(widget.projectId), (
      WritingState? previous,
      WritingState next,
    ) {
      if (previous?.activeScene?.id != next.activeScene?.id) {
        _clearSelection();
      }
    });
  }
}
