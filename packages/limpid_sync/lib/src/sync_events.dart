import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/src/conflict.dart';
import 'package:limpid_sync/src/errors.dart';
import 'package:limpid_sync/src/sync_state.dart';

/// An event published by the sync client.
///
/// The stream of events is the only way for the application to know what
/// happened to the document: the client never throws for a missing network,
/// it publishes the change of state instead.
sealed class SyncEvent {
  /// Creates an event.
  const SyncEvent(this.documentId);

  /// The document the event belongs to.
  final DocumentId documentId;
}

/// A locally authored operation was applied to the document.
final class SyncLocalOpApplied extends SyncEvent {
  /// Creates the event.
  const SyncLocalOpApplied(super.documentId, this.operation);

  /// The applied operation.
  final SyncOp operation;

  @override
  String toString() => 'SyncLocalOpApplied($operation)';
}

/// An operation received from the API was applied to the document.
final class SyncRemoteOpApplied extends SyncEvent {
  /// Creates the event.
  const SyncRemoteOpApplied(super.documentId, this.operation);

  /// The applied operation.
  final SyncOp operation;

  @override
  String toString() => 'SyncRemoteOpApplied($operation)';
}

/// The connectivity of the device changed.
final class SyncNetworkStatusChanged extends SyncEvent {
  /// Creates the event.
  const SyncNetworkStatusChanged(super.documentId, this.isOnline);

  /// Whether the API is reachable.
  final bool isOnline;

  @override
  String toString() => 'SyncNetworkStatusChanged($isOnline)';
}

/// The client failed.
final class SyncErrorRaised extends SyncEvent {
  /// Creates the event.
  const SyncErrorRaised(super.documentId, this.error);

  /// The error that occurred.
  final SyncException error;

  @override
  String toString() => 'SyncErrorRaised($error)';
}

/// Divergences were detected between the local and the remote versions of a
/// block.
///
/// The client never arbitrates: it publishes both versions so the author can
/// choose.
final class SyncConflictDetected extends SyncEvent {
  /// Creates the event.
  const SyncConflictDetected(super.documentId, this.reports);

  /// The detected divergences.
  final List<ConflictReport> reports;

  @override
  String toString() => 'SyncConflictDetected(${reports.length})';
}

/// The state of the client changed.
final class SyncStateChanged extends SyncEvent {
  /// Creates the event.
  const SyncStateChanged(super.documentId, this.state);

  /// The new state.
  final SyncState state;

  @override
  String toString() => 'SyncStateChanged($state)';
}
