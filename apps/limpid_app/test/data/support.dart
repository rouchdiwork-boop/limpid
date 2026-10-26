import 'dart:io';

import 'package:drift/native.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_core/limpid_core.dart';

/// Opens an in-memory database, for the tests that do not reopen it.
Future<AppDatabase> openMemoryDatabase() =>
    AppDatabase.openWith(NativeDatabase.memory());

/// Opens the database backed by [file], for the tests that reopen it.
Future<AppDatabase> openFileDatabase(File file) =>
    AppDatabase.openWith(NativeDatabase(file));

/// Builds an operation inserting a block in [documentId].
InsertBlockOp insertBlockOp({
  required String documentId,
  int lamport = 1,
  String authorId = 'author-1',
  String blockId = 'block-1',
  String text = 'Il pleuvait sur la falaise.',
}) => InsertBlockOp(
  doc: DocumentId(documentId),
  lamport: lamport,
  author: AuthorId(authorId),
  blockId: BlockId(blockId),
  parent: null,
  order: OrderKey('5'),
  type: BlockType.paragraph,
  content: TextContent(text),
);

/// Builds a project owned by [authorId].
Project projectOf({
  String id = 'project-1',
  String authorId = 'author-1',
  String title = 'Les Heures de Cendre',
  String synopsis = 'Une archiviste et une cloche.',
  ManuscriptStatus status = ManuscriptStatus.draft,
  bool isPublic = false,
  List<ChapterId> chapterIds = const <ChapterId>[],
  DateTime? updatedAt,
}) => Project(
  id: ProjectId(id),
  ownerId: AuthorId(authorId),
  title: title,
  synopsis: synopsis,
  status: status,
  isPublic: isPublic,
  order: OrderKey.initial,
  chapterIds: chapterIds,
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: updatedAt,
);

/// Builds a chapter of a project.
Chapter chapterOf({
  String id = 'chapter-1',
  String title = 'Le premier chapitre',
  List<SceneId> sceneIds = const <SceneId>[],
  DateTime? updatedAt,
}) => Chapter(
  id: ChapterId(id),
  title: title,
  order: OrderKey('5'),
  sceneIds: sceneIds,
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: updatedAt,
);

/// Builds a scene of a chapter.
Scene sceneOf({
  String id = 'scene-1',
  String chapterId = 'chapter-1',
  String documentId = 'document-1',
  String title = 'La falaise',
  int wordCount = 0,
  DateTime? updatedAt,
}) => Scene(
  id: SceneId(id),
  chapterId: ChapterId(chapterId),
  documentId: DocumentId(documentId),
  title: title,
  order: OrderKey('5'),
  wordCount: wordCount,
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: updatedAt,
);
