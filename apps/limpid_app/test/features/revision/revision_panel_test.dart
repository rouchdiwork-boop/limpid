import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_app/src/features/revision/revision_models.dart';
import 'package:limpid_app/src/features/revision/revision_panel.dart';
import 'package:limpid_app/src/features/revision/revision_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';

/// Gives the test a viewport large enough for the desktop layout.
void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Flushes the microtasks and the frames the panel needs.
Future<void> settle(WidgetTester tester) async {
  for (int frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Wraps the panel in a provider scope holding the fakes.
Widget harness({
  required List<RevisionThread> threads,
  List<ProjectMember> members = const <ProjectMember>[],
  FakeRevisionRepository? repository,
}) {
  return ProviderScope(
    overrides: [
      if (repository != null)
        revisionRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('fr'),
      home: Scaffold(
        body: RevisionPanel(
          projectId: kRevisionProjectId,
          threads: threads,
          members: members,
          currentAuthorId: kRevisionAuthor,
        ),
      ),
    ),
  );
}

/// The strings of the test.
AppLocalizations stringsOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(RevisionPanel)));

void main() {
  testWidgets('the panel lists the messages of the thread', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    final CommentThread thread = fakeThread(
      id: 'fil-1',
      markId: 'marque-1',
      comments: <Comment>[
        fakeComment(
          id: 'message-1',
          threadId: 'fil-1',
          authorId: 'auteur-1',
          body: 'Le sel vient des murs',
        ),
        fakeComment(
          id: 'message-2',
          threadId: 'fil-1',
          authorId: 'auteur-2',
          body: 'On l avait pose au chapitre I',
        ),
      ],
    );

    await tester.pumpWidget(
      harness(threads: <RevisionThread>[fakeRevisionThread(thread: thread)]),
    );
    await settle(tester);

    expect(find.text('Le sel vient des murs'), findsOneWidget);
    expect(find.text('On l avait pose au chapitre I'), findsOneWidget);
  });

  testWidgets('a closed thread leaves the open list', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    final CommentThread thread = fakeThread(
      id: 'fil-1',
      markId: 'marque-1',
      comments: <Comment>[
        fakeComment(
          id: 'message-1',
          threadId: 'fil-1',
          authorId: 'auteur-1',
          body: 'Le sel vient des murs',
        ),
      ],
      isResolved: true,
    );

    await tester.pumpWidget(
      harness(threads: <RevisionThread>[fakeRevisionThread(thread: thread)]),
    );
    await settle(tester);

    final AppLocalizations strings = stringsOf(tester);
    expect(find.text('Le sel vient des murs'), findsNothing);
    expect(find.text(strings.revisionResolved), findsOneWidget);
  });

  testWidgets('the panel shows the empty state without any comment', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));

    await tester.pumpWidget(harness(threads: const <RevisionThread>[]));
    await settle(tester);

    final AppLocalizations strings = stringsOf(tester);
    expect(find.byType(LimpidEmptyState), findsOneWidget);
    expect(find.text(strings.revisionEmptyMessage), findsOneWidget);
  });

  testWidgets('the panel shows the role of every collaborator', (tester) async {
    useSurface(tester, const Size(1440, 1100));

    await tester.pumpWidget(
      harness(
        threads: const <RevisionThread>[],
        members: <ProjectMember>[
          fakeMember(
            id: 'auteur-1',
            displayName: 'Ines Barreau',
            role: ProjectRole.owner,
          ),
          fakeMember(
            id: 'auteur-2',
            displayName: 'Thomas Derval',
            role: ProjectRole.betaReader,
          ),
          fakeMember(
            id: 'auteur-3',
            displayName: 'Malle Lenoir',
            role: ProjectRole.reader,
          ),
        ],
      ),
    );
    await settle(tester);

    final AppLocalizations strings = stringsOf(tester);
    expect(find.text(strings.revisionRoleOwner), findsOneWidget);
    expect(find.text(strings.revisionTitle), findsWidgets);
    expect(find.text(strings.revisionRoleReader), findsOneWidget);
    expect(find.byType(LimpidAvatar), findsNWidgets(3));
    expect(find.text('IB'), findsOneWidget);
  });

  testWidgets('the author of the book closes a thread and the state is kept', (
    tester,
  ) async {
    useSurface(tester, const Size(1440, 1100));
    final CommentThread thread = fakeThread(
      id: 'fil-1',
      markId: 'marque-1',
      comments: <Comment>[
        fakeComment(
          id: 'message-1',
          threadId: 'fil-1',
          authorId: 'auteur-2',
          body: 'Le sel vient des murs',
        ),
      ],
    );
    final FakeRevisionRepository repository = FakeRevisionRepository(
      threads: <CommentThread>[thread],
      members: <ProjectMember>[
        fakeMember(
          id: 'auteur-1',
          displayName: 'Ines Barreau',
          role: ProjectRole.owner,
        ),
      ],
    );

    await tester.pumpWidget(
      harness(
        threads: <RevisionThread>[fakeRevisionThread(thread: thread)],
        members: repository.members,
        repository: repository,
      ),
    );
    await settle(tester);

    final AppLocalizations strings = stringsOf(tester);
    await tester.tap(
      find.widgetWithText(LimpidButton, strings.revisionResolve),
    );
    await settle(tester);

    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.isResolved, isTrue);
    expect(repository.saved.single.resolvedAt, isNotNull);
  });

  testWidgets('a reader of the book cannot close a thread', (tester) async {
    useSurface(tester, const Size(1440, 1100));
    final CommentThread thread = fakeThread(
      id: 'fil-1',
      markId: 'marque-1',
      comments: <Comment>[
        fakeComment(
          id: 'message-1',
          threadId: 'fil-1',
          authorId: 'auteur-2',
          body: 'Le sel vient des murs',
        ),
      ],
    );
    final FakeRevisionRepository repository = FakeRevisionRepository(
      threads: <CommentThread>[thread],
      members: <ProjectMember>[
        fakeMember(
          id: 'auteur-1',
          displayName: 'Ines Barreau',
          role: ProjectRole.reader,
        ),
      ],
    );

    await tester.pumpWidget(
      harness(
        threads: <RevisionThread>[fakeRevisionThread(thread: thread)],
        members: repository.members,
        repository: repository,
      ),
    );
    await settle(tester);

    final AppLocalizations strings = stringsOf(tester);
    final LimpidButton button = tester.widget<LimpidButton>(
      find.widgetWithText(LimpidButton, strings.revisionResolve),
    );
    expect(button.onPressed, isNull);
  });

  group('the thread answers', () {
    /// The thread of the panel, with one message.
    CommentThread threadOfThePanel() => fakeThread(
      id: 'fil-1',
      markId: 'marque-1',
      comments: <Comment>[
        fakeComment(
          id: 'message-1',
          threadId: 'fil-1',
          authorId: 'auteur-2',
          body: 'Le sel vient des murs',
        ),
      ],
    );

    /// The repository of the panel, with its owner.
    FakeRevisionRepository repositoryOfThePanel(CommentThread thread) {
      return FakeRevisionRepository(
        threads: <CommentThread>[thread],
        members: <ProjectMember>[
          fakeMember(
            id: 'auteur-1',
            displayName: 'Ines Barreau',
            role: ProjectRole.owner,
          ),
        ],
      );
    }

    testWidgets('the reply is written at the end of the thread', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final CommentThread thread = threadOfThePanel();
      final FakeRevisionRepository repository = repositoryOfThePanel(thread);

      await tester.pumpWidget(
        harness(
          threads: <RevisionThread>[fakeRevisionThread(thread: thread)],
          members: repository.members,
          repository: repository,
        ),
      );
      await settle(tester);

      await tester.enterText(
        find.byType(TextField),
        'Oui, le sel vient de la falaise',
      );
      await settle(tester);
      await tester.tap(find.widgetWithText(LimpidButton, 'Répondre'));
      await settle(tester);

      expect(repository.saved, hasLength(1));
      final CommentThread saved = repository.saved.single;
      expect(saved.comments, hasLength(2));
      expect(saved.comments.first.body, 'Le sel vient des murs');
      expect(saved.comments.last.body, 'Oui, le sel vient de la falaise');
    });

    testWidgets('the reply carries the connected account and the date', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final CommentThread thread = threadOfThePanel();
      final FakeRevisionRepository repository = repositoryOfThePanel(thread);

      await tester.pumpWidget(
        harness(
          threads: <RevisionThread>[fakeRevisionThread(thread: thread)],
          members: repository.members,
          repository: repository,
        ),
      );
      await settle(tester);

      final DateTime before = DateTime.now();
      await tester.enterText(find.byType(TextField), 'D’accord');
      await settle(tester);
      await tester.tap(find.widgetWithText(LimpidButton, 'Répondre'));
      await settle(tester);

      final Comment reply = repository.saved.single.comments.last;
      expect(reply.author, kRevisionAuthor);
      expect(reply.threadId, thread.id);
      expect(reply.createdAt.isBefore(before), isFalse);
    });

    testWidgets('an empty reply is refused', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      final CommentThread thread = threadOfThePanel();
      final FakeRevisionRepository repository = repositoryOfThePanel(thread);

      await tester.pumpWidget(
        harness(
          threads: <RevisionThread>[fakeRevisionThread(thread: thread)],
          members: repository.members,
          repository: repository,
        ),
      );
      await settle(tester);

      final LimpidButton button = tester.widget<LimpidButton>(
        find.widgetWithText(LimpidButton, 'Répondre'),
      );
      expect(button.onPressed, isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await settle(tester);

      final LimpidButton stillEmpty = tester.widget<LimpidButton>(
        find.widgetWithText(LimpidButton, 'Répondre'),
      );
      expect(stillEmpty.onPressed, isNull);
      expect(repository.saved, isEmpty);
    });

    test('the controller refuses an empty reply', () async {
      final CommentThread thread = fakeThread(
        id: 'fil-1',
        markId: 'marque-1',
        comments: <Comment>[
          fakeComment(
            id: 'message-1',
            threadId: 'fil-1',
            authorId: 'auteur-2',
            body: 'Le sel vient des murs',
          ),
        ],
      );
      final FakeRevisionRepository repository = FakeRevisionRepository(
        threads: <CommentThread>[thread],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [revisionRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final RevisionController controller = container.read(
        revisionControllerProvider(kRevisionProjectId).notifier,
      );
      final bool written = await controller.reply(
        thread: thread,
        body: '   ',
        author: kRevisionAuthor,
      );

      expect(written, isFalse);
      expect(repository.saved, isEmpty);
    });
  });

  group('the thread is resolved and opened again', () {
    /// The thread of the panel, resolved.
    CommentThread resolvedThread() => fakeThread(
      id: 'fil-1',
      markId: 'marque-1',
      comments: <Comment>[
        fakeComment(
          id: 'message-1',
          threadId: 'fil-1',
          authorId: 'auteur-2',
          body: 'Le sel vient des murs',
        ),
      ],
      isResolved: true,
    );

    /// The repository of the panel, with its owner.
    FakeRevisionRepository repositoryOfThePanel(CommentThread thread) {
      return FakeRevisionRepository(
        threads: <CommentThread>[thread],
        members: <ProjectMember>[
          fakeMember(
            id: 'auteur-1',
            displayName: 'Ines Barreau',
            role: ProjectRole.owner,
          ),
        ],
      );
    }

    testWidgets('the resolved thread stays visible', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      final CommentThread thread = resolvedThread();
      final FakeRevisionRepository repository = repositoryOfThePanel(thread);

      await tester.pumpWidget(
        harness(
          threads: <RevisionThread>[fakeRevisionThread(thread: thread)],
          members: repository.members,
          repository: repository,
        ),
      );
      await settle(tester);

      final AppLocalizations strings = stringsOf(tester);
      await tester.tap(
        find.widgetWithText(LimpidChip, strings.revisionResolved),
      );
      await settle(tester);

      expect(find.text('Le sel vient des murs'), findsOneWidget);
    });

    testWidgets('the resolved thread is opened again', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      final CommentThread thread = resolvedThread();
      final FakeRevisionRepository repository = repositoryOfThePanel(thread);

      await tester.pumpWidget(
        harness(
          threads: <RevisionThread>[fakeRevisionThread(thread: thread)],
          members: repository.members,
          repository: repository,
        ),
      );
      await settle(tester);

      final AppLocalizations strings = stringsOf(tester);
      await tester.tap(
        find.widgetWithText(LimpidChip, strings.revisionResolved),
      );
      await settle(tester);
      await tester.tap(find.widgetWithText(LimpidButton, 'Rouvrir le fil'));
      await settle(tester);

      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.isResolved, isFalse);
      expect(repository.saved.single.resolvedAt, isNull);
    });

    testWidgets('the resolution carries its date', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      final CommentThread thread = fakeThread(
        id: 'fil-1',
        markId: 'marque-1',
        comments: <Comment>[
          fakeComment(
            id: 'message-1',
            threadId: 'fil-1',
            authorId: 'auteur-2',
            body: 'Le sel vient des murs',
          ),
        ],
      );
      final FakeRevisionRepository repository = repositoryOfThePanel(thread);

      await tester.pumpWidget(
        harness(
          threads: <RevisionThread>[fakeRevisionThread(thread: thread)],
          members: repository.members,
          repository: repository,
        ),
      );
      await settle(tester);

      final AppLocalizations strings = stringsOf(tester);
      final DateTime before = DateTime.now();
      await tester.tap(
        find.widgetWithText(LimpidButton, strings.revisionResolve),
      );
      await settle(tester);

      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.isResolved, isTrue);
      expect(repository.saved.single.resolvedAt, isNotNull);
      expect(repository.saved.single.resolvedAt!.isBefore(before), isFalse);
    });
  });
}
