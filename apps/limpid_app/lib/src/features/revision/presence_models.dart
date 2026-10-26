import 'package:flutter/foundation.dart';
import 'package:limpid_core/limpid_core.dart';

/// The scope of the presence: the project and the document being written.
///
/// The scope identifies the room of the relay: the document is the scene
/// being written, and the project is the one it belongs to.
@immutable
final class PresenceScope {
  /// Creates a scope.
  const PresenceScope({required this.projectId, this.documentId});

  /// The project being written.
  final String projectId;

  /// The document being written, `null` when no scene is opened.
  final String? documentId;

  /// Whether the scope follows a document.
  bool get hasDocument => documentId != null && documentId!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PresenceScope &&
          other.projectId == projectId &&
          other.documentId == documentId);

  @override
  int get hashCode => Object.hash(projectId, documentId);

  @override
  String toString() => 'PresenceScope($projectId, $documentId)';
}

/// The state of the relay for a document.
///
/// The state gathers what the relay brought: the peers it announced, the
/// operations it delivered and the state of the channel. The application
/// reads it and never talks to the relay itself.
@immutable
final class RealtimeState {
  /// Creates a state.
  const RealtimeState({
    this.peers = const <PresencePeer>[],
    this.operations = const <SyncOp>[],
    this.isConnected = false,
  });

  /// The peers present on the document.
  final List<PresencePeer> peers;

  /// The operations the relay delivered in the last frame.
  ///
  /// The list is empty for the frames that carry something else: the
  /// writing screen applies the operations it receives, and nothing else.
  final List<SyncOp> operations;

  /// Whether the channel of the document is open.
  final bool isConnected;

  /// Returns a copy of this state with the given fields replaced.
  RealtimeState copyWith({
    List<PresencePeer>? peers,
    List<SyncOp>? operations,
    bool? isConnected,
  }) {
    return RealtimeState(
      peers: peers ?? this.peers,
      operations: operations ?? this.operations,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RealtimeState &&
          other.peers == peers &&
          other.operations == operations &&
          other.isConnected == isConnected);

  @override
  int get hashCode => Object.hash(peers, operations, isConnected);

  @override
  String toString() =>
      'RealtimeState(${peers.length} peers, ${operations.length} ops)';
}

/// A peer present on the document, as the interface shows it.
@immutable
final class PresencePeerView {
  /// Creates a peer.
  const PresencePeerView({
    required this.userId,
    required this.displayName,
    this.paragraph,
  });

  /// The account of the peer.
  final String userId;

  /// The name the interface shows.
  final String displayName;

  /// The paragraph the caret of the peer stands in, `null` when the peer did
  /// not move its caret yet.
  final int? paragraph;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PresencePeerView &&
          other.userId == userId &&
          other.displayName == displayName &&
          other.paragraph == paragraph);

  @override
  int get hashCode => Object.hash(userId, displayName, paragraph);

  @override
  String toString() => 'PresencePeerView($userId, $displayName)';
}
