import 'package:limpid_sync/src/errors.dart';

/// The state of the synchronisation of a document.
enum SyncStatus {
  /// The document is synchronised; nothing is happening.
  idle,

  /// A synchronisation round trip is running.
  syncing,

  /// The API cannot be reached; the operations pile up in the local queue.
  offline,

  /// The last round trip failed for a reason the client cannot fix by
  /// itself (authentication, server error, conflict…).
  error,
}

/// The observable state of a synchronised document.
final class SyncState {
  /// Creates a state.
  const SyncState({
    this.status = SyncStatus.idle,
    this.pendingCount = 0,
    this.isOnline = true,
    this.lastSyncAt,
    this.lastError,
  });

  /// The current status.
  final SyncStatus status;

  /// The number of operations waiting to be sent to the API.
  final int pendingCount;

  /// Whether the API was reachable during the last check.
  final bool isOnline;

  /// The moment of the last successful round trip.
  final DateTime? lastSyncAt;

  /// The last error, `null` when the last round trip succeeded.
  final SyncException? lastError;

  /// Returns a copy of this state with the given fields replaced.
  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    bool? isOnline,
    DateTime? lastSyncAt,
    SyncException? lastError,
    bool clearError = false,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      isOnline: isOnline ?? this.isOnline,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  String toString() =>
      'SyncState($status, pending: $pendingCount, online: $isOnline)';
}
