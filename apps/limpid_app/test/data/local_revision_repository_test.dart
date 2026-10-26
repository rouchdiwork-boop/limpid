import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_revision_repository.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_core/limpid_core.dart';

import 'support.dart';

void main() {
  late AppDatabase database;
  late LocalRevisionRepository repository;

  setUp(() async {
    database = await openMemoryDatabase();
    repository = LocalRevisionRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  group('discussions', () {
    test('écrit un fil et le relit à l’identique', () async {
      final CommentThread thread = threadOf(
        id: 'thread-1',
        markId: 'mark-1',
        comments: <Comment>[
          commentOf(
            id: 'comment-1',
            threadId: 'thread-1',
            body: 'La falaise rend bien la scène.',
          ),
        ],
      );

      await repository.saveThread('project-1', thread);
      final List<CommentThread> threads = await repository.loadThreads(
        'project-1',
      );

      expect(threads, hasLength(1));
      expect(threads.single.id, const CommentId('thread-1'));
      expect(threads.single.markId, const MarkId('mark-1'));
      expect(threads.single.isResolved, isFalse);
      expect(threads.single.comments, hasLength(1));
      expect(
        threads.single.comments.single.body,
        'La falaise rend bien la scène.',
      );
      expect(threads.single.comments.single.author, const AuthorId('user-1'));
    });

    test('met à jour un fil déjà écrit', () async {
      await repository.saveThread('project-1', threadOf(id: 'thread-1'));

      await repository.saveThread(
        'project-1',
        threadOf(
          id: 'thread-1',
          isResolved: true,
          resolvedAt: DateTime.utc(2026, 10, 25, 9, 12),
          comments: <Comment>[
            commentOf(id: 'comment-1', threadId: 'thread-1'),
            commentOf(id: 'comment-2', threadId: 'thread-1'),
          ],
        ),
      );

      final List<CommentThread> threads = await repository.loadThreads(
        'project-1',
      );

      expect(threads, hasLength(1));
      expect(threads.single.isResolved, isTrue);
      expect(
        threads.single.resolvedAt?.isAtSameMomentAs(
          DateTime.utc(2026, 10, 25, 9, 12),
        ),
        isTrue,
      );
      expect(threads.single.comments, hasLength(2));
    });

    test('retire les messages qui ont quitté le fil', () async {
      await repository.saveThread(
        'project-1',
        threadOf(
          id: 'thread-1',
          comments: <Comment>[
            commentOf(id: 'comment-1', threadId: 'thread-1'),
            commentOf(id: 'comment-2', threadId: 'thread-1'),
          ],
        ),
      );

      await repository.saveThread(
        'project-1',
        threadOf(
          id: 'thread-1',
          comments: <Comment>[commentOf(id: 'comment-1', threadId: 'thread-1')],
        ),
      );

      final List<CommentThread> threads = await repository.loadThreads(
        'project-1',
      );

      expect(threads.single.comments, hasLength(1));
      expect(threads.single.comments.single.id, const CommentId('comment-1'));
    });

    test('ne rend aucun fil pour un projet inconnu', () async {
      await repository.saveThread('project-1', threadOf(id: 'thread-1'));

      final List<CommentThread> threads = await repository.loadThreads(
        'project-inconnu',
      );

      expect(threads, isEmpty);
    });

    test('sépare les discussions de deux projets', () async {
      await repository.saveThread('project-1', threadOf(id: 'thread-1'));
      await repository.saveThread('project-2', threadOf(id: 'thread-2'));

      expect(await repository.loadThreads('project-1'), hasLength(1));
      expect(await repository.loadThreads('project-2'), hasLength(1));
      expect(
        (await repository.loadThreads('project-1')).single.id,
        const CommentId('thread-1'),
      );
    });
  });

  group('persistance', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('limpid-revision-test');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('survit à une fermeture et à une réouverture de la base', () async {
      final File file = File('${directory.path}/limpid.sqlite');
      AppDatabase opened = await openFileDatabase(file);
      LocalRevisionRepository stored = LocalRevisionRepository(
        database: opened,
      );
      await stored.saveThread(
        'project-1',
        threadOf(
          id: 'thread-1',
          comments: <Comment>[commentOf(id: 'comment-1', threadId: 'thread-1')],
        ),
      );
      await opened.close();

      opened = await openFileDatabase(file);
      stored = LocalRevisionRepository(database: opened);
      final List<CommentThread> threads = await stored.loadThreads('project-1');

      expect(threads, hasLength(1));
      expect(threads.single.id, const CommentId('thread-1'));
      expect(threads.single.comments, hasLength(1));
      expect(
        threads.single.comments.single.body,
        'La falaise rend bien la scène.',
      );
      await opened.close();
    });
  });

  group('collaborateurs', () {
    test('ne rend aucun collaborateur pour un projet inconnu', () async {
      expect(await repository.loadMembers('project-inconnu'), isEmpty);
    });

    test('rend le propriétaire du projet', () async {
      await database.manuscripts.saveProject(projectOf(id: 'project-1'));

      final List<ProjectMember> members = await repository.loadMembers(
        'project-1',
      );

      expect(members, hasLength(1));
      expect(members.single.id, const AuthorId('author-1'));
      expect(members.single.role, ProjectRole.owner);
    });
  });
}

/// Builds a discussion anchored on [markId].
CommentThread threadOf({
  String id = 'thread-1',
  String markId = 'mark-1',
  bool isResolved = false,
  DateTime? resolvedAt,
  List<Comment> comments = const <Comment>[],
}) => CommentThread(
  id: CommentId(id),
  markId: MarkId(markId),
  comments: comments,
  isResolved: isResolved,
  resolvedAt: resolvedAt,
);

/// Builds a message of a discussion.
Comment commentOf({
  String id = 'comment-1',
  String threadId = 'thread-1',
  String authorId = 'user-1',
  String body = 'La falaise rend bien la scène.',
  DateTime? createdAt,
}) => Comment(
  id: CommentId(id),
  threadId: CommentId(threadId),
  author: AuthorId(authorId),
  body: body,
  createdAt: createdAt ?? DateTime.utc(2026, 10, 25, 9, 12),
);
