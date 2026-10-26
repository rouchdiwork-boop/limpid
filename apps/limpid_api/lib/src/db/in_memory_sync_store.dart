import 'sync_op_record.dart';
import 'sync_store.dart';

/// An in-memory [SyncStore], used by the test suite.
///
/// The store keeps the same invariants as the Postgres implementation: the
/// journal is append-only and an operation is stored once, identified by
/// `(doc_id, lamport, author_id)`.
final class InMemorySyncStore implements SyncStore {
  /// Creates an empty store.
  InMemorySyncStore();

  final Map<String, List<SyncOpRecord>> _operations =
      <String, List<SyncOpRecord>>{};
  final Map<String, Set<String>> _keys = <String, Set<String>>{};

  /// The operations currently stored, for the assertions of the test suite.
  List<SyncOpRecord> storedOperations(String projectId) =>
      List<SyncOpRecord>.unmodifiable(_operations[projectId] ?? const []);

  @override
  Future<AppendResult> append({
    required String projectId,
    required List<SyncOpRecord> operations,
  }) async {
    final List<SyncOpRecord> stored = _operations.putIfAbsent(
      projectId,
      () => <SyncOpRecord>[],
    );
    final Set<String> keys = _keys.putIfAbsent(projectId, () => <String>{});
    final List<SyncOpRecord> accepted = <SyncOpRecord>[];
    final List<SyncOpRecord> duplicated = <SyncOpRecord>[];

    for (final SyncOpRecord operation in operations) {
      if (keys.contains(operation.operationKey)) {
        duplicated.add(operation);
        continue;
      }
      keys.add(operation.operationKey);
      stored.add(operation);
      accepted.add(operation);
    }

    return AppendResult(
      accepted: accepted,
      duplicated: duplicated,
      maxLamport: _maxLamport(stored),
    );
  }

  @override
  Future<List<SyncOpRecord>> since({
    required String projectId,
    required int lamport,
    required int limit,
  }) async {
    final List<SyncOpRecord> matching =
        (_operations[projectId] ?? const [])
            .where((SyncOpRecord operation) => operation.lamport > lamport)
            .toList(growable: false)
          ..sort(_compareOperations);
    return matching.take(limit).toList(growable: false);
  }

  @override
  Future<List<SyncOpRecord>> all({required String projectId}) async {
    final List<SyncOpRecord> matching = List<SyncOpRecord>.of(
      _operations[projectId] ?? const [],
    )..sort(_compareOperations);
    return matching;
  }

  @override
  Future<Set<String>> projectsOfDocument(String docId) async {
    final Set<String> owners = <String>{};
    for (final List<SyncOpRecord> operations in _operations.values) {
      for (final SyncOpRecord operation in operations) {
        if (operation.docId == docId) owners.add(operation.projectId);
      }
    }
    return owners;
  }

  static int _compareOperations(SyncOpRecord left, SyncOpRecord right) {
    final int byLamport = left.lamport.compareTo(right.lamport);
    if (byLamport != 0) return byLamport;
    return left.authorId.compareTo(right.authorId);
  }

  /// The highest Lamport timestamp known for the project.
  ///
  /// The Postgres implementation answers the highest timestamp stored for
  /// the project, not the highest of the pushed batch: the answer is the
  /// server's view of the journal, whatever the client sent.
  static int _maxLamport(List<SyncOpRecord> operations) {
    var maxLamport = 0;
    for (final SyncOpRecord operation in operations) {
      if (operation.lamport > maxLamport) maxLamport = operation.lamport;
    }
    return maxLamport;
  }
}
