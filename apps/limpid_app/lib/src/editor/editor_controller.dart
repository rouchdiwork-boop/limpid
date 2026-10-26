import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_app/src/editor/editor_providers.dart';
import 'package:limpid_app/src/editor/editor_statistics.dart';
import 'package:limpid_core/limpid_core.dart';

/// The controller of the writing screen of a project.
///
/// It owns the scene being edited, the live document of that scene, the state
/// of the automatic save and the state of the assistant. The text itself
/// belongs to the editor widget: the controller only receives the operations
/// the editor produces and hands them over to the repository.
class WritingController extends Notifier<WritingState> {
  /// Creates the controller of a project.
  WritingController(this.projectId);

  /// The project being written.
  final String projectId;

  @override
  WritingState build() {
    ref.listen<AsyncValue<WritingOutline>>(writingOutlineProvider(projectId), (
      AsyncValue<WritingOutline>? previous,
      AsyncValue<WritingOutline> next,
    ) {
      _openFirstSceneOf(next);
    });

    // The outline may already be resolved when the controller is created —
    // the screen reads it first. The listener never fires in that case, so
    // the first scene is opened right away.
    final AsyncValue<WritingOutline> current = ref.read(
      writingOutlineProvider(projectId),
    );
    if (current.value != null) {
      Future<void>.microtask(() => _openFirstSceneOf(current));
    }

    return WritingState(projectId: projectId);
  }

  /// Opens the scene the author picked in the plan.
  Future<void> selectScene(OutlineScene outlineScene) async {
    if (state.activeScene?.id == outlineScene.id) {
      return;
    }
    await _loadScene(outlineScene);
  }

  /// Switches between the edition and the reading of the manuscript.
  void toggleReadMode() {
    state = state.copyWith(isReadMode: !state.isReadMode);
  }

  /// Hands the operations produced by the editor over to the repository.
  ///
  /// The operations are applied to the local document first, so that the
  /// counters follow the text immediately, then they are written by the
  /// repository, which queues them for the server.
  Future<void> applyOperations(List<SyncOp> operations) async {
    if (operations.isEmpty) {
      return;
    }
    final CrdtDocument? current = state.document;
    if (current == null) {
      return;
    }

    state = state.copyWith(
      saveState: EditorSaveState.saving,
      clearSaveError: true,
    );

    final CrdtDocument next;
    try {
      next = current.applyAll(operations);
    } on Object catch (error) {
      state = state.copyWith(
        saveState: EditorSaveState.failed,
        saveError: error,
      );
      return;
    }

    state = state.copyWith(
      document: next,
      wordCount: wordCountOf(next),
      lamport: _highestLamport(operations),
      saveState: EditorSaveState.saving,
    );

    try {
      await ref.read(manuscriptRepositoryProvider).applyOperations(operations);
      state = state.copyWith(saveState: EditorSaveState.saved);
    } on Object catch (error) {
      state = state.copyWith(
        saveState: EditorSaveState.failed,
        saveError: error,
      );
    }
  }

  /// Asks the assistant to work on the scene.
  ///
  /// The answer arrives as a stream of fragments: the panel shows them as
  /// they come, never at the end.
  Future<void> askAssistant(String instruction) async {
    final OutlineScene? scene = state.activeScene;
    if (scene == null || instruction.trim().isEmpty) {
      return;
    }
    final String selection = state.selection;

    state = state.copyWith(ai: const AiPanelState(isThinking: true));
    final StringBuffer buffer = StringBuffer();

    try {
      final AiRepository repository = ref.read(aiRepositoryProvider);
      final Stream<String> fragments = repository.rewrite(
        sceneId: scene.id.value,
        selection: selection,
        instruction: instruction,
      );
      await for (final String fragment in fragments) {
        buffer.write(fragment);
        if (state.activeScene?.id != scene.id) {
          return;
        }
        state = state.copyWith(
          ai: state.ai.copyWith(answer: buffer.toString()),
        );
      }
      state = state.copyWith(ai: state.ai.copyWith(isThinking: false));
    } on Object catch (error) {
      state = state.copyWith(
        ai: state.ai.copyWith(isThinking: false, error: error),
      );
    }
  }

  /// Closes the answer of the assistant.
  void dismissAssistant() {
    state = state.copyWith(ai: const AiPanelState());
  }

  /// Opens the first scene of the outline when no scene is opened yet.
  void _openFirstSceneOf(AsyncValue<WritingOutline> outline) {
    if (state.activeScene != null) {
      return;
    }
    final WritingOutline? value = outline.value;
    if (value == null) {
      return;
    }
    final OutlineScene? first = value.firstScene;
    if (first == null) {
      return;
    }
    unawaited(_loadScene(first));
  }

  /// Loads the document of a scene and makes it the active one.
  Future<void> _loadScene(OutlineScene outlineScene) async {
    state = state.copyWith(
      activeScene: outlineScene,
      isLoadingScene: true,
      clearDocument: true,
      wordCount: 0,
      lamport: 0,
      saveState: EditorSaveState.idle,
      clearSaveError: true,
      ai: const AiPanelState(),
    );

    try {
      final ManuscriptRepository repository = ref.read(
        manuscriptRepositoryProvider,
      );
      final CrdtDocument document = await repository.loadDocument(
        outlineScene.documentId.value,
      );
      if (state.activeScene?.id != outlineScene.id) {
        return;
      }
      state = state.copyWith(
        document: document,
        wordCount: wordCountOf(document),
        lamport: lamportOf(document),
        isLoadingScene: false,
      );
    } on Object catch (error) {
      if (state.activeScene?.id != outlineScene.id) {
        return;
      }
      state = state.copyWith(isLoadingScene: false, saveError: error);
    }
  }

  /// The highest Lamport timestamp carried by the operations.
  int _highestLamport(List<SyncOp> operations) {
    int lamport = state.lamport;
    for (final SyncOp operation in operations) {
      if (operation.lamport > lamport) {
        lamport = operation.lamport;
      }
    }
    return lamport;
  }
}

/// The controller of the writing screen, one per project.
final writingControllerProvider =
    NotifierProvider.family<WritingController, WritingState, String>(
      WritingController.new,
    );
