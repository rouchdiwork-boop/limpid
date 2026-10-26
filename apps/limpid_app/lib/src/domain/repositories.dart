import 'dart:typed_data';

import 'package:limpid_core/limpid_core.dart';

/// The state of the synchronisation, as the interface shows it.
///
/// The four states are the four the design system knows: the banner of the
/// application and the settings screen read them, and the design system
/// already carries the four labels.
enum SyncStatus {
  /// Every operation is saved on the server.
  synced,

  /// The local queue is being pushed.
  syncing,

  /// The device is offline: the operations wait in the durable local queue.
  offline,

  /// A conflict needs the attention of the author.
  conflict,
}

/// The reading and the writing of the manuscripts of the author.
///
/// The contract is deliberately **local first**: it always answers from the
/// SQLite database of the device, never from the network. The synchronisation
/// happens in the background, through [SyncRepository]. This is the promise
/// of the product — the application is fully usable offline.
///
/// The implementation lives in `lib/src/data/`.
abstract interface class ManuscriptRepository {
  /// The projects of the author, most recently updated first.
  Future<List<Project>> listProjects();

  /// A single project, `null` when it does not exist or was deleted.
  Future<Project?> findProject(String projectId);

  /// Creates a project and returns it.
  Future<Project> createProject({required String title, String synopsis});

  /// Saves the metadata of a project.
  ///
  /// The project carries the two states of the publication (D-33): the
  /// stage of the manuscript and its visibility in the showcase. Saving a
  /// project writes both.
  Future<Project> saveProject(Project project);

  /// Deletes a project, softly on the server and completely on the device.
  Future<void> deleteProject(String projectId);

  /// The chapters of a project, in reading order.
  Future<List<Chapter>> listChapters(String projectId);

  /// Creates or updates a chapter.
  Future<Chapter> saveChapter(Chapter chapter);

  /// The scenes of a chapter, in reading order.
  Future<List<Scene>> listScenes(String chapterId);

  /// Creates or updates a scene.
  Future<Scene> saveScene(Scene scene);

  /// The CRDT document of a scene: the block tree of the manuscript.
  ///
  /// An unknown document yields an empty document, never an error: a scene
  /// that was never edited is simply empty.
  Future<CrdtDocument> loadDocument(String documentId);

  /// Applies the operations produced by the editor.
  ///
  /// The operations are applied to the local document **and** queued for the
  /// server. Applying the same operation twice is a no-op: the CRDT is
  /// idempotent by construction.
  Future<void> applyOperations(List<SyncOp> operations);
}

/// The synchronisation of the local database with the server.
abstract interface class SyncRepository {
  /// The state of the synchronisation, right now.
  SyncStatus get status;

  /// The stream of the states of the synchronisation.
  Stream<SyncStatus> watch();

  /// Pushes the pending operations and pulls the remote ones.
  ///
  /// Never throws: an unreachable server leaves the status at
  /// [SyncStatus.offline] and the queue intact.
  Future<void> synchronize();
}

/// The file produced by an export.
final class ExportArtefact {
  /// Creates an artefact.
  const ExportArtefact({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  /// The recommended name of the file, extension included.
  final String fileName;

  /// The media type of the file.
  final String mimeType;

  /// The content of the file.
  final Uint8List bytes;
}

/// The exports of a manuscript.
///
/// The generation happens on the server: `POST /v1/export/<format>` builds the
/// book, writes the artefact in the object storage and **returns the file
/// itself**. There is no job to follow — the export of a manuscript is fast
/// enough to be synchronous, and a job would only add a round trip and a
/// state to lose.
abstract interface class ExportRepository {
  /// Exports the manuscript and returns the produced file.
  ///
  /// Throws a typed error when the server refuses the export — a manuscript
  /// with no content yet, an unknown format, a missing right.
  Future<ExportArtefact> export({
    required String projectId,
    required ExportFormat format,
  });
}

/// The preferences of the author that do not belong to a manuscript.
///
/// The daily goal is the only one for now: the number of words the author
/// aims to write every day. It is a preference of the author, not a property
/// of a book, and it is synchronized with the other devices like any other
/// setting (D-14).
abstract interface class PreferencesRepository {
  /// The number of words the author aims to write every day.
  ///
  /// A missing or corrupted preference yields the default goal of the design
  /// system, never an error: a preference must never break the interface.
  Future<int> dailyGoal();

  /// Sets the daily goal.
  Future<void> setDailyGoal(int words);

  /// The number of consecutive days on which the author wrote.
  ///
  /// A day counts when at least one word was written; a day without writing
  /// breaks the series.
  Future<int> writingStreak();
}

/// The assistant.
///
/// The answers arrive as a stream of fragments: the interface writes them as
/// they come, it never waits for the whole answer.
abstract interface class AiRepository {
  /// Answers a question about the book of the author.
  Stream<String> answer({required String projectId, required String question});

  /// Rewrites a selection of a scene.
  Stream<String> rewrite({
    required String sceneId,
    required String selection,
    required String instruction,
  });
}
