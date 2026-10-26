import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/editor/editor_controller.dart';
import 'package:limpid_app/src/editor/editor_providers.dart';
import 'package:limpid_core/limpid_core.dart';

import 'fakes.dart';

/// The identifier of the project used by the tests.
const String _projectId = 'projet-1';

/// The identifier of the document of the scene.
const DocumentId _documentId = DocumentId('scene-1-document');

void main() {
  test('l’éditeur enregistre les mots que l’auteur a ajoutés', () async {
    final FakeManuscriptRepository repository = _repository();
    final WritingController controller = await _controllerOf(repository);

    await controller.applyOperations(<SyncOp>[_paragraph('block-2')]);

    expect(repository.recordedWriting, hasLength(1));
    expect(repository.recordedWriting.single.words, 5);
    expect(repository.recordedWriting.single.projectId, _projectId);
  });

  test('une scène enregistrée puis réécrite ne compte qu’une fois', () async {
    final FakeManuscriptRepository repository = _repository();
    final WritingController controller = await _controllerOf(repository);
    final SyncOp operation = _paragraph('block-2');

    await controller.applyOperations(<SyncOp>[operation]);
    await controller.applyOperations(<SyncOp>[operation]);

    // Le CRDT est idempotent : la seconde frappe ne change pas le texte,
    // et la session ne compte donc pas les mots une seconde fois.
    expect(repository.recordedWriting, hasLength(1));
    expect(repository.recordedWriting.single.words, 5);
  });

  test('une suppression ne compte pas comme une écriture', () async {
    final FakeManuscriptRepository repository = _repository();
    final WritingController controller = await _controllerOf(repository);

    await controller.applyOperations(<SyncOp>[
      const DeleteBlockOp(
        doc: _documentId,
        lamport: 2,
        author: kFakeAuthor,
        blockId: BlockId('block-1'),
      ),
    ]);

    expect(repository.recordedWriting, isEmpty);
  });

  test('les opérations d’un autre auteur ne comptent pas', () async {
    final FakeManuscriptRepository repository = _repository();
    final WritingController controller = await _controllerOf(repository);

    controller.applyRemoteOperations(<SyncOp>[_paragraph('block-2')]);

    expect(repository.recordedWriting, isEmpty);
  });
}

/// The repository of the tests: a chapter, a scene and its document.
FakeManuscriptRepository _repository() {
  return FakeManuscriptRepository(
    chapters: <Chapter>[
      Chapter(
        id: const ChapterId('chapitre-1'),
        title: 'Le sel',
        order: OrderKey('1'),
      ),
    ],
    scenes: <String, List<Scene>>{
      'chapitre-1': <Scene>[
        Scene(
          id: const SceneId('scene-1'),
          chapterId: const ChapterId('chapitre-1'),
          documentId: _documentId,
          title: 'La plage à marée basse',
          order: OrderKey('1'),
          wordCount: 3,
        ),
      ],
    },
    documents: <String, CrdtDocument>{
      'scene-1-document': fakeDocument(
        documentId: 'scene-1-document',
        text: 'Bonjour le monde',
      ),
    },
  );
}

/// Opens the controller of the project and waits for the scene to be loaded.
Future<WritingController> _controllerOf(
  FakeManuscriptRepository repository,
) async {
  final ProviderContainer container = ProviderContainer(
    overrides: [manuscriptRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);

  final WritingController controller = container.read(
    writingControllerProvider(_projectId).notifier,
  );
  await container.read(writingOutlineProvider(_projectId).future);
  for (int attempt = 0; attempt < 50; attempt++) {
    if (controller.state.document != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(controller.state.document, isNotNull);
  return controller;
}

/// The operation that adds a paragraph of five words.
SyncOp _paragraph(String blockId) => InsertBlockOp(
  doc: _documentId,
  lamport: 2,
  author: kFakeAuthor,
  blockId: BlockId(blockId),
  parent: null,
  order: OrderKey('2'),
  type: BlockType.paragraph,
  content: const TextContent('La mer se retirait lentement'),
);
