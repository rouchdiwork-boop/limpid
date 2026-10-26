import 'package:limpid_core/limpid_core.dart';

export 'export_repository.dart';

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

/// The technical code of the refusal of the protocol version of the client.
///
/// The server answers `409 schema_version_unsupported` when the version of
/// the protocol the client speaks is older than the oldest version the
/// server still accepts.
const String schemaVersionUnsupportedCode = 'schema_version_unsupported';

/// The server refused the protocol version of the client.
///
/// The client does not speak the language of the server any more: it pulls
/// the tree of the project, replaces its local state by the one of the
/// server and replays the operations the server has not accepted yet.
///
/// The error never reaches the interface: the client repairs itself, alone.
final class SchemaVersionUnsupportedException implements Exception {
  /// Creates the error.
  const SchemaVersionUnsupportedException({required this.message});

  /// The explanation of the refusal, as the server wrote it.
  final String message;

  @override
  String toString() => 'SchemaVersionUnsupportedException: $message';
}

/// An event of the synchronisation.
///
/// The events tell what the synchronisation does from the inside: a
/// resynchronization, a refusal of the server. They never ask anything to
/// the author — the client catches up by itself.
sealed class SyncEvent {
  /// Creates an event.
  const SyncEvent();
}

/// The server refused the protocol version of the client: the client
/// resynchronizes itself.
///
/// The event opens the resynchronization: the client pulls the tree of the
/// project, replaces its local state by the one of the server and replays
/// the operations the server has not accepted yet.
final class SyncResynchronizing extends SyncEvent {
  /// Creates an event.
  const SyncResynchronizing({
    required this.documentId,
    required this.projectId,
  });

  /// The document being resynchronised.
  final String documentId;

  /// The project the document belongs to.
  final String projectId;

  @override
  String toString() => 'SyncResynchronizing($documentId, project: $projectId)';
}

/// The resynchronization is over.
final class SyncResynchronized extends SyncEvent {
  /// Creates an event.
  const SyncResynchronized({
    required this.documentId,
    required this.replacedDocuments,
    required this.replayedOperations,
  });

  /// The document whose local state was replaced by the one of the server.
  final String documentId;

  /// The number of documents the tree of the server described.
  final int replacedDocuments;

  /// The number of local operations that were replayed.
  final int replayedOperations;

  @override
  String toString() =>
      'SyncResynchronized($documentId, replayed: $replayedOperations)';
}

/// The server refused an operation.
///
/// The operation stays in the durable queue of the device: it is never
/// dropped, and the author is told about it.
final class SyncRefused extends SyncEvent {
  /// Creates an event.
  const SyncRefused({
    required this.operationKey,
    required this.code,
    required this.message,
  });

  /// The identity of the refused operation.
  final String operationKey;

  /// The stable, technical reason of the refusal.
  final String code;

  /// The explanation of the refusal.
  final String message;

  @override
  String toString() => 'SyncRefused($operationKey, $code)';
}

/// A repository of synchronisation that tells what it does.
///
/// The contract of the synchronisation only exposes the state of the
/// synchronisation. This optional capability exposes the **events**: the
/// resynchronizations, the refusals of the server.
abstract interface class SyncEventSource {
  /// The stream of the events of the synchronisation.
  Stream<SyncEvent> watchEvents();
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

  /// The series of a project, in reading order.
  ///
  /// The series is the first level of the hierarchy of a book (D-02): it
  /// groups the tomes of the project.
  Future<List<Series>> listSeries(String projectId);

  /// Creates a series in a project and returns it.
  ///
  /// The series is written and attached to the project: it survives the
  /// restart of the application and comes back with the project.
  Future<Series> createSeries({
    required String projectId,
    required String title,
    String synopsis = '',
  });

  /// The volumes of a series, in reading order.
  Future<List<Volume>> listVolumes(String seriesId);

  /// The chapters of a volume, in reading order.
  ///
  /// The chapters a volume holds are the ones that hang on it; the other
  /// chapters of the project belong to the project itself.
  Future<List<Chapter>> listChaptersOfVolume(String volumeId);

  /// Creates a volume in a series and returns it.
  Future<Volume> createVolume({
    required String seriesId,
    required String title,
    String synopsis = '',
  });

  /// Creates a chapter and returns it.
  ///
  /// The chapter hangs on [volumeId] when it is given, and directly on the
  /// project otherwise: a book does not have to use the series and the
  /// volume levels.
  Future<Chapter> createChapter({
    required String projectId,
    String? volumeId,
    required String title,
    String synopsis = '',
  });

  /// Creates a scene in a chapter and returns it.
  ///
  /// The scene owns a CRDT document: the creation writes its title in that
  /// document, so the scene is a real scene — it is found again after the
  /// restart, and it synchronizes like any other writing.
  Future<Scene> createScene({
    required String chapterId,
    required String title,
    String synopsis = '',
  });

  /// Moves a scene inside its chapter and returns it.
  ///
  /// The move changes the fractional index of the scene and nothing else:
  /// the text of the scene never moves. The new index is computed between
  /// the order keys of the new neighbours, so an index that exists is never
  /// rewritten (D-04).
  Future<Scene> moveScene({required String sceneId, required int targetIndex});

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
  ///
  /// The one exception is the refusal of the second factor: the server
  /// refuses the operations when the proof is missing, and the application
  /// can repair that by asking the author for a code. The refusal therefore
  /// reaches the caller, and the operations stay in the queue.
  Future<void> synchronize();
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

/// A day of writing, as the statistics of the author read it.
///
/// A session carries what the author **wrote** that day — never the size
/// of the chapters they touched. The words are counted by difference: a
/// scene that is saved again without a change does not count twice.
///
/// The session is a **local** fact: it belongs to the device and never
/// leaves it.
final class WritingSession {
  /// Creates a session.
  const WritingSession({
    required this.day,
    required this.words,
    this.minutes = 0,
    this.projectId = '',
  });

  /// The day of the session, at the local midnight.
  ///
  /// The day is **local**: the author writes on their own days, not on the
  /// days of the universal time zone.
  final DateTime day;

  /// The number of words the author wrote that day.
  final int words;

  /// The number of minutes the author wrote that day.
  final int minutes;

  /// The book the session belongs to.
  ///
  /// The identifier is empty for the **total** of the author: the total is
  /// the sum of the books, and it is the row the series of the writing days
  /// counts.
  final String projectId;
}

/// The writing sessions of the author.
///
/// The contract is **local**: the sessions are written on the device and are
/// never synchronized — the criterion asks for statistics that work
/// offline.
///
/// The days of writing come from the sessions, never from the date the
/// scenes were modified: re-reading a book is not writing, and the counter
/// of words of a chapter written three weeks ago does not belong to today.
///
/// A repository that does not know the sessions — the demonstration mode,
/// for instance — simply does not implement this contract: the screens then
/// show no history rather than an invented one.
///
/// The contract **extends** [ManuscriptRepository]: the sessions belong to
/// the manuscripts of the author, and a repository that knows the sessions
/// knows the manuscripts too.
abstract interface class WritingSessionRepository
    implements ManuscriptRepository {
  /// Records the words the author wrote in [projectId].
  ///
  /// The words are the ones the author **added**: the session of the day
  /// grows by that amount, and never by the size of the chapter.
  ///
  /// The minutes are the time the author spent writing; they are the time
  /// between two strokes, and never the time the application stayed open.
  Future<void> recordWriting({
    required String projectId,
    required int words,
    required int minutes,
  });

  /// The sessions written between [from] and [to], both included.
  ///
  /// The sessions are the ones of the author of the session: they are
  /// ordered from the most recent day to the oldest one.
  Future<List<WritingSession>> writingSessions({
    required DateTime from,
    required DateTime to,
  });
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
