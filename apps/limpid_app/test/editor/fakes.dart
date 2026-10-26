import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_core/limpid_core.dart';

/// The author used by the fakes.
const AuthorId kFakeAuthor = AuthorId('auteur-1');

/// A manuscript repository backed by in-memory chapters, scenes and documents.
///
/// The fake records the operations the editor hands over, so that a test can
/// assert that an edition reaches the repository.
final class FakeManuscriptRepository implements ManuscriptRepository {
  /// Creates the fake.
  FakeManuscriptRepository({
    this.chapters = const <Chapter>[],
    this.scenes = const <String, List<Scene>>{},
    this.documents = const <String, CrdtDocument>{},
  });

  /// The chapters of the project, in reading order.
  final List<Chapter> chapters;

  /// The scenes of every chapter, keyed by the identifier of the chapter.
  final Map<String, List<Scene>> scenes;

  /// The document of every scene, keyed by the identifier of the document.
  final Map<String, CrdtDocument> documents;

  /// The batches of operations the editor handed over to the repository.
  final List<List<SyncOp>> appliedOperations = <List<SyncOp>>[];

  /// Every operation the editor handed over to the repository.
  List<SyncOp> get operations => <SyncOp>[
    for (final List<SyncOp> batch in appliedOperations) ...batch,
  ];

  @override
  Future<List<Chapter>> listChapters(String projectId) async => chapters;

  @override
  Future<List<Scene>> listScenes(String chapterId) async =>
      scenes[chapterId] ?? const <Scene>[];

  @override
  Future<CrdtDocument> loadDocument(String documentId) async =>
      documents[documentId] ?? CrdtDocument.empty(DocumentId(documentId));

  @override
  Future<void> applyOperations(List<SyncOp> operations) async {
    appliedOperations.add(List<SyncOp>.unmodifiable(operations));
  }

  @override
  Future<List<Project>> listProjects() async => const <Project>[];

  @override
  Future<Project?> findProject(String projectId) async => null;

  @override
  Future<Project> createProject({required String title, String synopsis = ''}) {
    throw UnimplementedError('The fake repository does not create projects.');
  }

  @override
  Future<Project> saveProject(Project project) {
    throw UnimplementedError('The fake repository does not save projects.');
  }

  @override
  Future<void> deleteProject(String projectId) {
    throw UnimplementedError('The fake repository does not delete projects.');
  }

  @override
  Future<Chapter> saveChapter(Chapter chapter) {
    throw UnimplementedError('The fake repository does not save chapters.');
  }

  @override
  Future<Scene> saveScene(Scene scene) {
    throw UnimplementedError('The fake repository does not save scenes.');
  }
}

/// A synchronisation repository driven by the test.
final class FakeSyncRepository implements SyncRepository {
  /// Creates the fake.
  FakeSyncRepository({this.status = SyncStatus.synced});

  /// The state of the synchronisation, right now.
  @override
  SyncStatus status;

  final StreamController<SyncStatus> _controller =
      StreamController<SyncStatus>.broadcast();

  @override
  Stream<SyncStatus> watch() async* {
    yield status;
    yield* _controller.stream;
  }

  @override
  Future<void> synchronize() async {}

  /// Publishes a new state of the synchronisation.
  void emit(SyncStatus next) {
    status = next;
    _controller.add(next);
  }

  /// Closes the stream of the states.
  Future<void> close() => _controller.close();
}

/// A request of rewriting the assistant received.
@immutable
class FakeAiRequest {
  /// Creates a request.
  const FakeAiRequest({
    required this.sceneId,
    required this.selection,
    required this.instruction,
  });

  /// The scene the assistant works on.
  final String sceneId;

  /// The text the assistant works on.
  final String selection;

  /// The instruction of the author.
  final String instruction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FakeAiRequest &&
          other.sceneId == sceneId &&
          other.selection == selection &&
          other.instruction == instruction);

  @override
  int get hashCode => Object.hash(sceneId, selection, instruction);

  @override
  String toString() => 'FakeAiRequest($sceneId, $instruction)';
}

/// An assistant answering with a stream of fragments.
final class FakeAiRepository implements AiRepository {
  /// Creates the fake.
  FakeAiRepository({List<String> fragments = const <String>[]})
    : fragments = List<String>.of(fragments);

  /// The fragments of every answer.
  final List<String> fragments;

  /// The requests the assistant received.
  final List<FakeAiRequest> requests = <FakeAiRequest>[];

  @override
  Stream<String> rewrite({
    required String sceneId,
    required String selection,
    required String instruction,
  }) async* {
    requests.add(
      FakeAiRequest(
        sceneId: sceneId,
        selection: selection,
        instruction: instruction,
      ),
    );
    for (final String fragment in fragments) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      yield fragment;
    }
  }

  @override
  Stream<String> answer({
    required String projectId,
    required String question,
  }) async* {
    for (final String fragment in fragments) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      yield fragment;
    }
  }
}

/// Builds a chapter of the fake repository.
Chapter fakeChapter({required String id, required String title}) =>
    Chapter(id: ChapterId(id), title: title, order: OrderKey.initial);

/// Builds a scene of the fake repository.
Scene fakeScene({
  required String id,
  required String chapterId,
  required String title,
  int wordCount = 0,
}) => Scene(
  id: SceneId(id),
  chapterId: ChapterId(chapterId),
  documentId: DocumentId('$id-document'),
  title: title,
  order: OrderKey.initial,
  wordCount: wordCount,
);

/// Builds the document of a scene: one paragraph holding [text].
CrdtDocument fakeDocument({
  required String documentId,
  required String text,
  String blockId = 'block-1',
}) {
  final DocumentId id = DocumentId(documentId);
  return CrdtDocument.empty(id).apply(
    InsertBlockOp(
      doc: id,
      lamport: 1,
      author: kFakeAuthor,
      blockId: BlockId(blockId),
      parent: null,
      order: OrderKey.initial,
      type: BlockType.paragraph,
      content: TextContent(text),
    ),
  );
}
