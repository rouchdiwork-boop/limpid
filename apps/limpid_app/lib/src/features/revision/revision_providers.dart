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
final revisionThreadsProvider =
    FutureProvider.family<List<CommentThread>, String>((
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
  const RevisionState({this.isResolving = false, this.error});

  /// Whether a discussion is being closed.
  final bool isResolving;

  /// The error raised by the last action, `null` when it succeeded.
  final Object? error;

  /// Whether the panel may act.
  bool get canAct => !isResolving;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevisionState &&
          other.isResolving == isResolving &&
          other.error == error);

  @override
  int get hashCode => Object.hash(isResolving, error);

  @override
  String toString() => 'RevisionState(isResolving: $isResolving)';
}

/// The actions of the review panel of a project.
final revisionControllerProvider =
    NotifierProvider.family<RevisionController, RevisionState, String>(
      RevisionController.new,
    );

/// The controller of the review panel of a project.
///
/// It closes the discussions and writes them: the state of a closed
/// discussion survives the panel, and the manuscript keeps its anchor.
class RevisionController extends Notifier<RevisionState> {
  /// Creates the controller of a project.
  RevisionController(this.projectId);

  /// The project being reviewed.
  final String projectId;

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
    state = const RevisionState(isResolving: true);
    try {
      final CommentThread resolved = thread.copyWith(
        isResolved: true,
        resolvedAt: DateTime.now(),
      );
      await ref
          .read(revisionRepositoryProvider)
          .saveThread(projectId, resolved);
      ref.invalidate(revisionThreadsProvider(projectId));
      state = const RevisionState();
    } on Exception catch (error) {
      state = RevisionState(error: error);
    }
  }

  /// Forgets the error of the last action.
  ///
  /// The panel calls it once it has shown the failure: the state keeps the
  /// error until somebody reads it, and not one moment longer.
  void clearError() {
    if (state.error == null) {
      return;
    }
    state = RevisionState(isResolving: state.isResolving);
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
