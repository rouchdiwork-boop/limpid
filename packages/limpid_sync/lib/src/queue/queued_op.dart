import 'package:limpid_core/limpid_core.dart';

/// The state of an operation inside the local queue.
enum OpQueueStatus {
  /// The operation is waiting to be sent to the API.
  pending,

  /// The API acknowledged the operation; it can be purged.
  sent,

  /// The last attempt failed; the operation will be retried after a backoff.
  failed,
}

/// An operation waiting in the local queue.
///
/// The queue entry is immutable: every transition produces a new instance,
/// which keeps the persisted rows and the in-memory store consistent.
final class QueuedOp {
  /// Creates a queue entry.
  const QueuedOp({
    required this.operation,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.lastAttemptAt,
    this.nextAttemptAt,
    this.lastError,
  });

  /// Creates a pending entry for [operation].
  factory QueuedOp.pending(SyncOp operation, {DateTime? createdAt}) {
    return QueuedOp(
      operation: operation,
      status: OpQueueStatus.pending,
      attempts: 0,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  /// The operation carried by the entry.
  final SyncOp operation;

  /// The state of the entry.
  final OpQueueStatus status;

  /// The number of attempts already made.
  final int attempts;

  /// The moment the operation entered the queue.
  final DateTime createdAt;

  /// The moment of the last attempt.
  final DateTime? lastAttemptAt;

  /// The earliest moment the next attempt may happen.
  final DateTime? nextAttemptAt;

  /// The reason of the last failure.
  final String? lastError;

  /// The identity of the operation, used for deduplication.
  String get operationKey => operation.operationKey;

  /// The document the operation belongs to.
  String get documentId => operation.doc.value;

  /// The Lamport timestamp of the operation.
  int get lamport => operation.lamport;

  /// The author of the operation.
  String get authorId => operation.author.value;

  /// Whether the operation can be sent right now.
  bool isReadyAt(DateTime now) {
    if (status == OpQueueStatus.sent) return false;
    final next = nextAttemptAt;
    if (next == null) return true;
    return !now.isBefore(next);
  }

  /// Returns a copy of this entry with the given fields replaced.
  QueuedOp copyWith({
    OpQueueStatus? status,
    int? attempts,
    DateTime? lastAttemptAt,
    DateTime? nextAttemptAt,
    String? lastError,
    bool clearNextAttemptAt = false,
    bool clearLastError = false,
  }) {
    return QueuedOp(
      operation: operation,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextAttemptAt: clearNextAttemptAt
          ? null
          : (nextAttemptAt ?? this.nextAttemptAt),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  String toString() => 'QueuedOp($operationKey, $status, attempts: $attempts)';
}
