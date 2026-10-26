import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/limpid_sync.dart';

/// The snapshots of the documents of one account.
///
/// ## The leak this view closes
///
/// The table of the snapshots is unique per device and keyed by the document
/// alone: the CRDT journal of a manuscript downloaded by an account stays in
/// the file, and another account could read it back.
///
/// ## The key of the storage
///
/// The view stores the snapshot of a document under the key of the account
/// that owns it — `<account>/<document>`. The key of the storage is therefore
/// never ambiguous, and the document the application works with keeps its
/// own identifier: the journal is restored under the identifier of the
/// scene, not under the key of the storage.
///
/// The account is resolved on every call: a change of account takes effect
/// at once, without reopening the database.
final class AccountSnapshotStore implements SnapshotStore {
  /// Creates a view of [delegate] restricted to the account of [accountId].
  AccountSnapshotStore({required this.delegate, required this.accountId});

  /// The shared snapshots of the device.
  final SnapshotStore delegate;

  /// The identifier of the account whose snapshots the view exposes.
  final String Function() accountId;

  @override
  Future<DocumentSnapshot?> read(DocumentId documentId) async {
    final DocumentSnapshot? stored = await delegate.read(_key(documentId));
    if (stored == null) return null;
    return DocumentSnapshot(
      documentId: documentId,
      since: stored.since,
      maxLamport: stored.maxLamport,
      operations: stored.operations,
      state: stored.state,
    );
  }

  @override
  Future<void> write(DocumentSnapshot snapshot) async {
    await delegate.write(
      DocumentSnapshot(
        documentId: _key(snapshot.documentId),
        since: snapshot.since,
        maxLamport: snapshot.maxLamport,
        operations: snapshot.operations,
        state: snapshot.state,
      ),
    );
  }

  @override
  Future<void> remove(DocumentId documentId) =>
      delegate.remove(_key(documentId));

  /// The key the snapshot of [documentId] is stored under.
  DocumentId _key(DocumentId documentId) =>
      DocumentId('${accountId()}/${documentId.value}');
}
