import 'account_purge_store.dart';
import 'audit_entry.dart';

/// An operation of the synchronisation journal, in memory.
typedef _Operation = ({String projectId, String authorId});

/// A collaboration on a project, in memory.
typedef _Membership = ({String projectId, String userId});

/// A purge recorded by the store, in memory.
typedef _Purge = ({
  DateTime requestedAt,
  DateTime scheduledFor,
  DateTime purgedAt,
  String workerId,
});

/// An in-memory [AccountPurgeStore], used by the test suite.
///
/// The store keeps the same invariants as the SQL implementation: the erase
/// covers the projects of the account, the operations of the synchronisation
/// journal that belong to them, the collaborations and the personal data of
/// the account, and an account that was already purged is left untouched.
///
/// The journal is given to the store: it is the list of the entries of the
/// audit log, and the store only reads it.
final class InMemoryAccountPurgeStore implements AccountPurgeStore {
  /// Creates a store reading the deletion requests in [entries].
  ///
  /// The entries are the ones of the audit log: the store only reads them.
  InMemoryAccountPurgeStore({required List<AuditEntry> entries})
    : _journal = entries;

  /// The entries of the journal, read by the store.
  final List<AuditEntry> _journal;

  /// The projects of the database, by identifier and owner.
  final Map<String, String> _projects = <String, String>{};

  /// The operations of the synchronisation journal, by identifier.
  final Map<String, _Operation> _operations = <String, _Operation>{};

  /// The collaborations, by identifier.
  final Map<String, _Membership> _members = <String, _Membership>{};

  /// The messages of the discussions, by identifier and author.
  final Map<String, String> _messages = <String, String>{};

  /// The purges already performed, by account.
  final Map<String, _Purge> _purges = <String, _Purge>{};

  /// Adds a project owned by [ownerId] to the database.
  void addProject({required String projectId, required String ownerId}) {
    _projects[projectId] = ownerId;
  }

  /// Adds an operation to the synchronisation journal.
  void addOperation({
    required String operationId,
    required String projectId,
    required String authorId,
  }) {
    _operations[operationId] = (projectId: projectId, authorId: authorId);
  }

  /// Adds a collaboration on a project to the database.
  void addMember({required String projectId, required String userId}) {
    _members['$projectId:$userId'] = (projectId: projectId, userId: userId);
  }

  /// Adds a message written by [authorId] to the database.
  void addMessage({required String messageId, required String authorId}) {
    _messages[messageId] = authorId;
  }

  /// The projects left in the database, by identifier and owner.
  Map<String, String> get projects =>
      Map<String, String>.unmodifiable(_projects);

  /// The identifiers of the operations left in the synchronisation journal.
  List<String> get operationIds => List<String>.unmodifiable(_operations.keys);

  /// The identifiers of the collaborations left in the database.
  List<String> get memberIds => List<String>.unmodifiable(_members.keys);

  /// The accounts already purged.
  Set<String> get purgedAccounts => Set<String>.unmodifiable(_purges.keys);

  /// The number of rows of the account left in the database.
  int remainingRows(String userId) {
    final int projects = _projects.values
        .where((String owner) => owner == userId)
        .length;
    final int operations = _operations.values
        .where(
          (_Operation operation) =>
              operation.authorId == userId ||
              _projects[operation.projectId] == userId,
        )
        .length;
    final int collaborations = _members.values
        .where((_Membership member) => member.userId == userId)
        .length;
    final int messages = _messages.values
        .where((String author) => author == userId)
        .length;
    return projects + operations + collaborations + messages;
  }

  @override
  Future<List<AuditEntry>> journalEntries({
    required String action,
    required int limit,
  }) async {
    final List<AuditEntry> matching =
        _journal
            .where((AuditEntry entry) => entry.action == action)
            .toList(growable: false)
          ..sort((AuditEntry left, AuditEntry right) {
            final int byDate = _momentOf(left).compareTo(_momentOf(right));
            if (byDate != 0) return byDate;
            return left.targetId.compareTo(right.targetId);
          });
    return List<AuditEntry>.unmodifiable(matching.take(limit));
  }

  @override
  Future<AccountPurgeOutcome> purge({
    required String userId,
    required DateTime requestedAt,
    required DateTime scheduledFor,
    required DateTime purgedAt,
    required String workerId,
  }) async {
    final _Purge? existing = _purges[userId];
    if (existing != null) {
      return AccountPurgeOutcome(
        userId: userId,
        projectsDeleted: 0,
        operationsDeleted: 0,
        collaborationsDeleted: 0,
        messagesDeleted: 0,
        purged: false,
      );
    }

    _purges[userId] = (
      requestedAt: requestedAt,
      scheduledFor: scheduledFor,
      purgedAt: purgedAt,
      workerId: workerId,
    );

    final int messages = _removeMatching(
      _messages,
      (String author) => author == userId,
    );
    final int operations = _removeMatching(
      _operations,
      (_Operation operation) =>
          operation.authorId == userId ||
          _projects[operation.projectId] == userId,
    );
    final int collaborations = _removeMatching(
      _members,
      (_Membership member) => member.userId == userId,
    );
    final int projects = _removeMatching(
      _projects,
      (String owner) => owner == userId,
    );

    return AccountPurgeOutcome(
      userId: userId,
      projectsDeleted: projects,
      operationsDeleted: operations,
      collaborationsDeleted: collaborations,
      messagesDeleted: messages,
      purged: true,
    );
  }

  /// The moment of an entry, the epoch when it carries none.
  static DateTime _momentOf(AuditEntry entry) =>
      entry.createdAt?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Removes the rows matching [test] and answers their number.
  ///
  /// The rows are collected before they are removed: the removal of a row
  /// must never change the answer of the test of the next one.
  static int _removeMatching<V>(
    Map<String, V> rows,
    bool Function(V value) test,
  ) {
    final List<String> keys = <String>[];
    for (final MapEntry<String, V> entry in rows.entries) {
      if (test(entry.value)) keys.add(entry.key);
    }
    for (final String key in keys) {
      rows.remove(key);
    }
    return keys.length;
  }
}
