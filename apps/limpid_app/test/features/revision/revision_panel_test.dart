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
}
