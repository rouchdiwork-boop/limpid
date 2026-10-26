import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/document_op_queue_store.dart';
import 'package:limpid_app/src/data/project_ops_transport.dart';
import 'package:limpid_app/src/data/server_tree.dart';
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';

/// What a resynchronization did.
final class ResynchronizationReport {
  /// Creates a report.
  const ResynchronizationReport({
    required this.replacedDocuments,
    required this.replayedOperations,
  });

  /// The number of documents the tree of the server described.
  final int replacedDocuments;

  /// The number of local operations that were replayed.
  final int replayedOperations;

  @override
  String toString() =>
      'ResynchronizationReport(replaced: $replacedDocuments, '
      'replayed: $replayedOperations)';
}

/// The resynchronization of the local state with the server.
///
/// ## What it does
///
/// The server refused the version of the protocol of the client: the server
/// is newer, and the journal it holds is the most complete. The client
/// therefore pulls the tree of the project, **replaces** the local state of
/// the document by the one of the server, and **replays** the operations the
/// server has not accepted yet on top of it.
///
/// The server makes the authority: the state of the client is the state of
/// the server, plus the operations the server does not know yet.
///
/// ## What it never does
///
/// The resynchronization never drops an operation. The operations waiting in
/// the durable queue are replayed, and the ones the server refuses again
/// stay in the queue with the reason of their refusal.
final class SyncResynchronizer {
  /// Creates a resynchronizer.
  SyncResynchronizer({
    required this.database,
    required this.transport,
    required this.author,
  });

  /// The local database of the application.
  final AppDatabase database;

  /// The transport reaching the API.
  final SyncTransport transport;

  /// The author of the local operations.
  ///
  /// The author is resolved on every call: it follows the session, and the
  /// operations of another account never leave the device under this one.
  final AuthorId Function() author;

  final Map<String, List<ServerDocumentTree>> _trees =
      <String, List<ServerDocumentTree>>{};

  /// Resynchronizes the document [documentId] with the server.
  ///
  /// Throws a [SyncTransportException] when the transport cannot pull the
  /// tree of the project.
  Future<ResynchronizationReport> resynchronize({
    required String documentId,
    required String projectId,
  }) async {
    final List<ServerDocumentTree> trees = await _treeOf(projectId);
    final ServerDocumentTree? tree = _treeOfDocument(trees, documentId);

    final DocumentId id = DocumentId(documentId);
    await database
        .snapshotsFor(() => author().value)
        .write(
          DocumentSnapshot(
            documentId: id,
            since: 0,
            maxLamport: tree?.lamport ?? 0,
            // The journal is empty: the state of the server holds the
            // operations it accepted, and the operations it has not accepted
            // yet are replayed from the queue.
            operations: const <SyncOp>[],
            state: tree?.toState() ?? CrdtState.empty(id),
          ),
        );

    return ResynchronizationReport(
      replacedDocuments: trees.length,
      replayedOperations: await _prepareTheReplay(documentId),
    );
  }

  /// Forgets the trees pulled during the previous round.
  ///
  /// The tree of a project is pulled once per round: the documents of the
  /// project share it, and the server does not change while the round runs.
  void forgetTrees() => _trees.clear();

  /// The tree of the project [projectId], pulled once per round.
  Future<List<ServerDocumentTree>> _treeOf(String projectId) async {
    final List<ServerDocumentTree>? known = _trees[projectId];
    if (known != null) return known;
    final SyncTransport current = transport;
    if (current is! TreeFetchingTransport) {
      throw const SyncTransportException(
        'The transport cannot pull the tree of a project.',
        code: 'sync_unsupported',
      );
    }
    final List<ServerDocumentTree> pulled = await current.fetchTree(projectId);
    _trees[projectId] = pulled;
    return pulled;
  }

  /// The tree of the document [documentId], `null` when the server knows
  /// none.
  ///
  /// The server knows none when it never accepted an operation of the
  /// document: the local state is then replaced by the empty state, and the
  /// operations of the queue rebuild the document.
  static ServerDocumentTree? _treeOfDocument(
    List<ServerDocumentTree> trees,
    String documentId,
  ) {
    for (final ServerDocumentTree tree in trees) {
      if (tree.documentId == documentId) return tree;
    }
    return null;
  }

  /// Prepares the replay of the operations the server has not accepted.
  ///
  /// The operations that failed wait for a backoff before their next
  /// attempt: the resynchronization is the moment to send them again, and
  /// the backoff is dropped. The operation itself never changes.
  Future<int> _prepareTheReplay(String documentId) async {
    final DocumentOpQueueStore store = DocumentOpQueueStore(
      delegate: database.queueFor(() => author().value),
      documentId: documentId,
    );
    final List<QueuedOp> entries = await store.all();
    final List<QueuedOp> replayed = <QueuedOp>[
      for (final QueuedOp entry in entries)
        if (entry.status != OpQueueStatus.sent)
          QueuedOp.pending(entry.operation, createdAt: entry.createdAt),
    ];
    if (replayed.isEmpty) return 0;
    await store.putAll(replayed);
    return replayed.length;
  }
}
