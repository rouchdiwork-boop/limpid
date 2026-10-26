import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/revision_repository.dart';
import 'package:limpid_core/limpid_core.dart';

/// The repository holding the discussions of the projects.
///
/// The provider is **not** wired by default: the implementation lives in the
/// data layer, and the composition root of the application overrides it. The
/// default keeps the discussions in the memory of the process, so that the
/// review stays usable before the durable storage exists.
final Provider<RevisionRepository> revisionRepositoryProvider =
    Provider<RevisionRepository>((Ref ref) {
      return InMemoryRevisionRepository();
    });

/// The discussions anchored on the manuscripts of a project.
///
/// Every discussion carries the excerpt it holds: the words the author
/// commented.
final revisionThreadsProvider =
    FutureProvider.family<List<StoredThread>, String>((
      Ref ref,
      String projectId,
    ) async {
      final RevisionRepository repository = ref.watch(
        revisionRepositoryProvider,
      );
      return repository.loadThreads(projectId);
    });

/// The collaborators of a project, with the role they hold.
final revisionMembersProvider =
    FutureProvider.family<List<ProjectMember>, String>((
      Ref ref,
      String projectId,
    ) async {
      final RevisionRepository repository = ref.watch(
        revisionRepositoryProvider,
      );
      return repository.loadMembers(projectId);
    });

/// The state of the actions of the review panel.
@immutable
class RevisionState {
  /// Creates a state.
  const RevisionState({this.isWriting = false, this.error});

  /// Whether a discussion is being written.
  final bool isWriting;

  /// The error raised by the last action, `null` when it succeeded.
  final Object? error;

  /// Whether the panel may act.
  bool get canAct => !isWriting;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevisionState &&
          other.isWriting == isWriting &&
          other.error == error);

  @override
  int get hashCode => Object.hash(isWriting, error);

  @override
  String toString() => 'RevisionState(isWriting: $isWriting)';
}

/// The actions of the review panel of a project.
final revisionControllerProvider =
    NotifierProvider.family<RevisionController, RevisionState, String>(
      RevisionController.new,
    );

/// The controller of the review panel of a project.
///
/// It answers the discussions, closes them and opens them again, then writes
/// them: the state of a discussion survives the panel, and the manuscript
/// keeps its anchor.
class RevisionController extends Notifier<RevisionState> {
  /// Creates the controller of a project.
  RevisionController(this.projectId);

  /// The project being reviewed.
  final String projectId;

  /// The generator of the identifiers of the replies.
  final UlidGenerator _ids = UlidGenerator();

  @override
  RevisionState build() => const RevisionState();

  /// Closes the discussion and writes it.
  ///
  /// The error is kept in the state: the panel shows it and the author may
  /// try again.
  Future<void> resolve(CommentThread thread) async {
    if (!state.canAct) {
      return;
    }
    await _write(thread.resolve(DateTime.now()));
  }

  /// Opens the discussion again and writes it.
  ///
  /// The reopened discussion keeps no date of resolution.
  Future<void> reopen(CommentThread thread) async {
    if (!state.canAct) {
      return;
    }
    await _write(thread.reopen());
  }

  /// Adds a reply to the discussion and writes it.
  ///
  /// An empty reply is refused: a discussion never holds an empty message.
  /// The reply carries the account of [author] and the date of the writing.
  /// The reply is added at the end of the discussion: the messages stay
  /// ordered from the oldest to the newest.
  ///
  /// Returns whether the reply was written.
  Future<bool> reply({
    required CommentThread thread,
    required String body,
    required AuthorId author,
  }) async {
    if (!state.canAct) {
      return false;
    }
    final String text = body.trim();
    if (text.isEmpty) {
      return false;
    }
    final Comment answer = Comment(
      id: CommentId(_ids.generate().value),
      threadId: thread.id,
      author: author,
      body: text,
      createdAt: DateTime.now(),
    );
    return _write(
      thread.copyWith(comments: <Comment>[...thread.comments, answer]),
    );
  }

  /// Creates the discussion of a comment and writes it.
  ///
  /// The discussion is anchored on the mark [markId] — the mark that covers
  /// the passage the author selected — and it holds the message of the
  /// author, his account and the date of the writing. The excerpt holds the
  /// words the author commented.
  ///
  /// An empty message is refused: a discussion never holds an empty message.
  ///
  /// Returns whether the discussion was written.
  Future<bool> createThread({
    required MarkId markId,
    required String body,
    required String excerpt,
    required AuthorId author,
  }) async {
    if (!state.canAct) {
      return false;
    }
    final String text = body.trim();
    if (text.isEmpty) {
      return false;
    }
    final CommentId threadId = CommentId(_ids.generate().value);
    final CommentThread thread = CommentThread(
      id: threadId,
      markId: markId,
      comments: <Comment>[
        Comment(
          id: CommentId(_ids.generate().value),
          threadId: threadId,
          author: author,
          body: text,
          createdAt: DateTime.now(),
        ),
      ],
    );
    return _write(thread, excerpt: _excerptOf(excerpt));
  }

  /// Writes the discussion [thread] and keeps the state of the panel.
  ///
  /// The excerpt is written when the discussion is created: a reply or a
  /// resolution leaves it untouched.
  ///
  /// Returns whether the discussion was written. The error is kept in the
  /// state: the panel shows it and the author may try again.
  Future<bool> _write(CommentThread thread, {String excerpt = ''}) async {
    state = const RevisionState(isWriting: true);
    try {
      await ref
          .read(revisionRepositoryProvider)
          .saveThread(projectId, thread, excerpt: excerpt);
      ref.invalidate(revisionThreadsProvider(projectId));
      state = const RevisionState();
      return true;
    } on Exception catch (error) {
      state = RevisionState(error: error);
      return false;
    }
  }

  /// The excerpt of the discussion, cut to the length the server accepts.
  ///
  /// The cut never separates a surrogate pair: the excerpt stays a text the
  /// server can read.
  String _excerptOf(String excerpt) {
    if (excerpt.length <= maxRevisionExcerptLength) {
      return excerpt;
    }
    int end = maxRevisionExcerptLength;
    final int last = excerpt.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) {
      end -= 1;
    }
    return excerpt.substring(0, end);
  }

  /// Forgets the error of the last action.
  ///
  /// The panel calls it once it has shown the failure: the state keeps the
  /// error until somebody reads it, and not one moment longer.
  void clearError() {
    if (state.error == null) {
      return;
    }
    state = RevisionState(isWriting: state.isWriting);
  }
}

/// The comment selected in the review panel of a project.
@immutable
class RevisionSelection {
  /// Creates a selection.
  const RevisionSelection({this.anchorId, this.threadId});

  /// The identifier of the selected anchor, `null` when nothing is selected.
  final String? anchorId;

  /// The identifier of the selected discussion, `null` when nothing is
  /// selected.
  final String? threadId;

  /// Whether the panel holds no selection.
  bool get isEmpty => anchorId == null;

  /// Whether the anchor [id] is the selected one.
  bool isSelected(String id) => anchorId == id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevisionSelection &&
          other.anchorId == anchorId &&
          other.threadId == threadId);

  @override
  int get hashCode => Object.hash(anchorId, threadId);

  @override
  String toString() => 'RevisionSelection($anchorId)';
}

/// The selection of the review panel of a project.
final revisionSelectionProvider =
    NotifierProvider.family<
      RevisionSelectionNotifier,
      RevisionSelection,
      String
    >(RevisionSelectionNotifier.new);

/// The controller of the selection of the review panel.
///
/// The selection is the way the panel and the manuscript talk to each other:
/// the panel asks for an anchor, the manuscript puts it in relief.
class RevisionSelectionNotifier extends Notifier<RevisionSelection> {
  /// Creates the controller of a project.
  RevisionSelectionNotifier(this.projectId);

  /// The project being reviewed.
  final String projectId;

  @override
  RevisionSelection build() => const RevisionSelection();

  /// Selects the anchor of a discussion.
  void select({required String anchorId, String? threadId}) {
    state = RevisionSelection(anchorId: anchorId, threadId: threadId);
  }

  /// Drops the selection.
  void clear() {
    state = const RevisionSelection();
  }
}
