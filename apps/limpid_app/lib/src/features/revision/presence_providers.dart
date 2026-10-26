import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/realtime.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/revision/presence_models.dart';
import 'package:limpid_core/limpid_core.dart';

/// The state of the relay for the document of the scope.
///
/// The relay owns the presence: the provider keeps the last known state of
/// every peer and forgets the peers that left. The application only reads
/// the state — it never talks to the relay itself.
///
/// The provider is the **only** follower of the document: the presence and
/// the operations of the relay travel together, and the screen that writes
/// listens to them both.
final realtimeProvider = StreamProvider.family<RealtimeState, PresenceScope>((
  ref,
  scope,
) async* {
  final SyncRepository repository = ref.watch(syncRepositoryProvider);
  if (repository is! RealTimeSyncRepository) return;
  final String? documentId = scope.documentId;
  if (documentId == null || documentId.isEmpty) return;
  ref.onDispose(() => unawaited(repository.release(documentId)));

  final Map<String, PresencePeer> peers = <String, PresencePeer>{};
  var isConnected = false;

  await for (final RealTimeEvent event in repository.follow(documentId)) {
    var operations = const <SyncOp>[];
    if (event is RealTimePresence) {
      _remember(peers, event.peer);
    } else if (event is RealTimeOperations) {
      operations = event.operations;
    } else if (event is RealTimeConnection) {
      isConnected = event.isConnected;
    }
    yield RealtimeState(
      peers: List<PresencePeer>.unmodifiable(peers.values),
      operations: operations,
      isConnected: isConnected,
    );
  }
});

/// Keeps the last known state of [peer].
///
/// A peer that left is forgotten; a peer that moved its caret keeps the
/// identity the relay gave it when it joined.
void _remember(Map<String, PresencePeer> peers, PresencePeer peer) {
  if (peer.state == PresenceState.left) {
    peers.remove(peer.userId);
    return;
  }
  final PresencePeer? known = peers[peer.userId];
  peers[peer.userId] = known == null
      ? peer
      : known.copyWith(state: peer.state, cursor: peer.cursor);
}
