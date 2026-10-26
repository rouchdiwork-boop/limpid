import 'package:flutter/foundation.dart';
import 'package:limpid_core/limpid_core.dart';

/// The state of the automatic save of the manuscript.
///
/// The state never guesses: it is driven by the operations the editor
/// produces and by the answers of the repository.
enum EditorSaveState {
  /// Nothing has been written since the last save.
  idle,

  /// The operations are on their way to the local database.
  saving,

  /// The operations are written and queued for the server.
  saved,

  /// The operations could not be written.
  failed,
}

/// A scene of the outline of a project.
///
/// The scene carries its position in the book — the chapter and the scene
/// numbers — so that the interface can label it without recomputing the
/// hierarchy.
@immutable
class OutlineScene {
  /// Creates an outline scene.
  const OutlineScene({
    required this.scene,
    required this.chapterNumber,
    required this.sceneNumber,
  });

  /// The scene of the repository.
  final Scene scene;

  /// The number of the chapter, starting at 1.
  final int chapterNumber;

  /// The number of the scene inside its chapter, starting at 1.
  final int sceneNumber;

  /// The identifier of the scene.
  SceneId get id => scene.id;

  /// The title of the scene.
  String get title => scene.title;

  /// The number of words the repository knows about the scene.
  int get wordCount => scene.wordCount;

  /// The CRDT document holding the text of the scene.
  DocumentId get documentId => scene.documentId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutlineScene &&
          other.scene == scene &&
          other.chapterNumber == chapterNumber &&
          other.sceneNumber == sceneNumber);

  @override
  int get hashCode => Object.hash(scene, chapterNumber, sceneNumber);

  @override
  String toString() => 'OutlineScene($id, $title)';
}

/// A chapter of the outline of a project.
@immutable
class OutlineChapter {
  /// Creates an outline chapter.
  const OutlineChapter({required this.chapter, required this.scenes});

  /// The chapter of the repository.
  final Chapter chapter;

  /// The scenes of the chapter, in reading order.
  final List<OutlineScene> scenes;

  /// The title of the chapter.
  String get title => chapter.title;

  /// The number of words targeted by the chapter.
  int get targetWordCount => chapter.targetWordCount;
}

/// A tome of the outline of a project.
///
/// The tome is the level between the series and the chapter (D-02).
@immutable
class OutlineVolume {
  /// Creates an outline volume.
  const OutlineVolume({required this.volume, required this.chapters});

  /// The tome of the repository.
  final Volume volume;

  /// The chapters of the tome, in reading order.
  final List<OutlineChapter> chapters;

  /// The title of the tome.
  String get title => volume.title;
}

/// A series of the outline of a project.
///
/// The series is the first level of the hierarchy of a book (D-02): it
/// groups the tomes of the project.
@immutable
class OutlineSeries {
  /// Creates an outline series.
  const OutlineSeries({required this.series, required this.volumes});

  /// The series of the repository.
  final Series series;

  /// The tomes of the series, in reading order.
  final List<OutlineVolume> volumes;

  /// The title of the series.
  String get title => series.title;
}

/// The outline of a project: its series, its tomes, its chapters and their
/// scenes.
///
/// The outline is a projection of the repository, never a hard coded list.
/// The hierarchy of D-02 is whole: a book holds series, a series holds
/// tomes, a tome holds chapters, and a chapter holds scenes. A book that
/// does not use the series and the tome levels holds its chapters directly.
@immutable
class WritingOutline {
  /// Creates an outline.
  const WritingOutline({
    this.series = const <OutlineSeries>[],
    this.chapters = const <OutlineChapter>[],
  });

  /// An outline without any chapter.
  static const WritingOutline empty = WritingOutline(
    series: <OutlineSeries>[],
    chapters: <OutlineChapter>[],
  );

  /// The series of the project, in reading order.
  final List<OutlineSeries> series;

  /// The chapters that hang directly on the project, in reading order.
  final List<OutlineChapter> chapters;

  /// Every chapter of the project, in reading order.
  ///
  /// The chapters of the tomes come first, then the chapters of the
  /// project: the number a chapter carries is its number in the book.
  List<OutlineChapter> get allChapters => <OutlineChapter>[
    for (final OutlineSeries series in series)
      for (final OutlineVolume volume in series.volumes) ...volume.chapters,
    ...chapters,
  ];

  /// Every scene of the project, in reading order.
  List<OutlineScene> get scenes => <OutlineScene>[
    for (final OutlineChapter chapter in allChapters) ...chapter.scenes,
  ];

  /// The first scene of the project, `null` when the project is empty.
  OutlineScene? get firstScene {
    for (final OutlineChapter chapter in allChapters) {
      if (chapter.scenes.isNotEmpty) {
        return chapter.scenes.first;
      }
    }
    return null;
  }

  /// Whether the plan holds no row at all.
  ///
  /// The plan is empty when it carries neither a series, nor a tome, nor a
  /// chapter: the author has not built anything yet. A series without a tome
  /// is **not** empty — the plan shows the series and lets the author add a
  /// tome to it. The scenes do not decide: a book may have a plan before it
  /// has a single scene.
  bool get isPlanEmpty => series.isEmpty && chapters.isEmpty;
}

/// The state of the assistant panel.
@immutable
class AiPanelState {
  /// Creates an assistant state.
  const AiPanelState({this.isThinking = false, this.answer = '', this.error});

  /// Whether the assistant is still writing its answer.
  final bool isThinking;

  /// The answer received so far.
  final String answer;

  /// The error raised by the assistant, `null` when it answered.
  final Object? error;

  /// Whether an answer is available.
  bool get hasAnswer => answer.isNotEmpty;

  /// Returns a copy of this state with the given fields replaced.
  AiPanelState copyWith({
    bool? isThinking,
    String? answer,
    Object? error,
    bool clearError = false,
  }) {
    return AiPanelState(
      isThinking: isThinking ?? this.isThinking,
      answer: answer ?? this.answer,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// The state of the writing screen of a project.
@immutable
class WritingState {
  /// Creates a writing state.
  const WritingState({
    required this.projectId,
    this.activeScene,
    this.document,
    this.wordCount = 0,
    this.lamport = 0,
    this.saveState = EditorSaveState.idle,
    this.saveError,
    this.isLoadingScene = false,
    this.isReadMode = false,
    this.ai = const AiPanelState(),
  });

  /// The project being written.
  final String projectId;

  /// The scene currently opened, `null` when none is.
  final OutlineScene? activeScene;

  /// The CRDT document of the opened scene, `null` while it loads.
  final CrdtDocument? document;

  /// The number of words of the opened scene, computed from its content.
  final int wordCount;

  /// The Lamport timestamp of the last operation applied locally.
  final int lamport;

  /// The state of the automatic save.
  final EditorSaveState saveState;

  /// The error raised by the last save, `null` when it succeeded.
  final Object? saveError;

  /// Whether the document of the scene is being loaded.
  final bool isLoadingScene;

  /// Whether the screen shows the manuscript instead of editing it.
  final bool isReadMode;

  /// The state of the assistant panel.
  final AiPanelState ai;

  /// The text the assistant works on: the prose of the opened scene.
  String get selection {
    final CrdtDocument? current = document;
    if (current == null) {
      return '';
    }
    return current.blocks
        .where((Block block) => !block.deleted)
        .map((Block block) => block.content.plainText)
        .join('\n')
        .trim();
  }

  /// Returns a copy of this state with the given fields replaced.
  WritingState copyWith({
    OutlineScene? activeScene,
    CrdtDocument? document,
    int? wordCount,
    int? lamport,
    EditorSaveState? saveState,
    Object? saveError,
    bool? isLoadingScene,
    bool? isReadMode,
    AiPanelState? ai,
    bool clearDocument = false,
    bool clearSaveError = false,
  }) {
    return WritingState(
      projectId: projectId,
      activeScene: activeScene ?? this.activeScene,
      document: clearDocument ? null : (document ?? this.document),
      wordCount: wordCount ?? this.wordCount,
      lamport: lamport ?? this.lamport,
      saveState: saveState ?? this.saveState,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
      isLoadingScene: isLoadingScene ?? this.isLoadingScene,
      isReadMode: isReadMode ?? this.isReadMode,
      ai: ai ?? this.ai,
    );
  }
}
