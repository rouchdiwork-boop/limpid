import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_app/src/editor/editor_providers.dart';
import 'package:limpid_app/src/editor/editor_statistics.dart';
import 'package:limpid_app/src/features/actions/remote_runner.dart';
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

  /// Creates a series in the project of the screen.
  ///
  /// The series is the first level of the hierarchy of the book (D-02): the
  /// author creates it from the plan, and it is written through the
  /// manuscript repository — like every other writing.
  Future<void> createSeries(String title) async {
    await _write(() async {
      await ref
          .read(manuscriptRepositoryProvider)
          .createSeries(projectId: projectId, title: title);
    });
  }

  /// Creates a tome in a series of the project.
  Future<void> createVolume(String seriesId, String title) async {
    await _write(() async {
      await ref
          .read(manuscriptRepositoryProvider)
          .createVolume(seriesId: seriesId, title: title);
    });
  }

  /// Creates a chapter in a tome, or directly in the project.
  Future<void> createChapter(String? volumeId, String title) async {
    await _write(() async {
      await ref
          .read(manuscriptRepositoryProvider)
          .createChapter(
            projectId: projectId,
            volumeId: volumeId,
            title: title,
          );
    });
  }

  /// Creates a scene in a chapter and opens it.
  ///
  /// The scene is written through the manuscript repository, and the plan is
  /// read again : l'auteur écrit tout de suite dans la scène qu'il vient
  /// de créer.
  Future<void> createScene(String chapterId, String title) async {
    Scene? created;
    await _write(() async {
      created = await ref
          .read(manuscriptRepositoryProvider)
          .createScene(chapterId: chapterId, title: title);
    });
    if (created == null) return;
    ref.invalidate(writingOutlineProvider(projectId));
    final WritingOutline outline = await ref.read(
      writingOutlineProvider(projectId).future,
    );
    for (final OutlineScene candidate in outline.scenes) {
      if (candidate.id != created!.id) continue;
      await selectScene(candidate);
      return;
    }
  }

  /// Moves a scene inside its chapter.
  ///
  /// The move changes the fractional index of the scene and nothing else :
  /// the text of the scene never moves.
  Future<void> moveScene(String sceneId, int targetIndex) async {
    await _write(() async {
      await ref
          .read(manuscriptRepositoryProvider)
          .moveScene(sceneId: sceneId, targetIndex: targetIndex);
    });
  }

  /// Writes the manuscript and reads the plan again.
  ///
  /// The failure of the write is kept in the state : the status bar shows
  /// it, and the author knows that the plan did not change.
  Future<void> _write(Future<void> Function() action) async {
    state = state.copyWith(
      saveState: EditorSaveState.saving,
      clearSaveError: true,
    );
    try {
      await action();
      ref.invalidate(writingOutlineProvider(projectId));
      state = state.copyWith(saveState: EditorSaveState.saved);
    } on Object catch (error) {
      state = state.copyWith(
        saveState: EditorSaveState.failed,
        saveError: error,
      );
    }
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

  /// Applies the operations another author produced.
  ///
  /// The relay delivered them: the text of the other author appears in the
  /// document of the screen, and the counters follow it.
  ///
  /// The operations are **not** written to the queue of the device: the
  /// server already knows them, and pushing them back would forge their
  /// authorship. The durable journal of the device is written by the
  /// repository of the synchronisation.
  void applyRemoteOperations(List<SyncOp> operations) {
    if (operations.isEmpty) return;
    final CrdtDocument? current = state.document;
    if (current == null) return;
    final CrdtDocument next = current.applyAll(operations);
    state = state.copyWith(
      document: next,
      wordCount: wordCountOf(next),
      lamport: _highestLamport(operations),
    );
  }

  /// Asks the assistant to work on the scene.
  ///
  /// The answer arrives as a stream of fragments: the panel shows them as
  /// they come, never at the end.
  ///
  /// The remote call goes through [runner]: when the server refuses the
  /// proof of the second factor, the runner asks a code to the author and
  /// **repeats** the call. The answer of the refused call never reached the
  /// panel — the server refuses before it answers — so the repetition starts
  /// from a clean answer.
  Future<void> askAssistant(
    String instruction, {
    required RemoteRunner runner,
  }) async {
    final OutlineScene? scene = state.activeScene;
    if (scene == null || instruction.trim().isEmpty) {
      return;
    }
    final String selection = state.selection;

    state = state.copyWith(ai: const AiPanelState(isThinking: true));

    try {
      await runner<void>(() async {
        final AiRepository repository = ref.read(aiRepositoryProvider);
        final Stream<String> fragments = repository.rewrite(
          sceneId: scene.id.value,
          selection: selection,
          instruction: instruction,
        );
        final StringBuffer buffer = StringBuffer();
        await for (final String fragment in fragments) {
          buffer.write(fragment);
          if (state.activeScene?.id != scene.id) {
            return;
          }
          state = state.copyWith(
            ai: state.ai.copyWith(answer: buffer.toString()),
          );
        }
      });
      state = state.copyWith(ai: state.ai.copyWith(isThinking: false));
    } on Exception catch (error) {
      state = state.copyWith(
        ai: state.ai.copyWith(isThinking: false, error: error),
      );
    } on Object catch (error, stackTrace) {
      // Une `Error` — et non une `Exception` — ne remonte pas dans le
      // `on Exception` ci-dessus : sans ce filet, l'échec disparaît et le
      // panneau ne dit rien. Le panneau montre le motif, et la console porte
      // la cause.
      state = state.copyWith(
        ai: state.ai.copyWith(isThinking: false, error: error),
      );
      debugPrint('La demande à l\'assistant a échoué : $error\n$stackTrace');
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
