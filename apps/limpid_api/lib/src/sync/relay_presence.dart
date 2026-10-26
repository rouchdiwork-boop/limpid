import 'dart:async';

import 'package:limpid_core/limpid_core.dart';

import '../services/sync_hub.dart';

/// Broadcasts a presence frame to the room of a document.
///
/// [except] designates the subscriber that produced the frame: it does not
/// receive its own message, exactly like the operations.
typedef PresenceBroadcaster =
    void Function(
      String projectId,
      String docId,
      Map<String, Object?> frame, {
      SyncSubscription? except,
    });

/// The presence of a connection of the relay.
///
/// The relay **owns** the presence: it announces the joins, the cursor moves
/// and the departures, and it purges the peers that stopped beating. A
/// client never announces that it left — it simply stops beating, and the
/// relay removes it.
///
/// ## The heartbeat
///
/// The connection beats every [heartbeatInterval]: the relay sends it a
/// `ping` and the client answers. A connection that stayed silent for more
/// than [presenceTimeout] is purged: its rooms are left, and the other peers
/// are told that it is gone.
final class RelayPresence {
  /// Creates the presence of a connection.
  RelayPresence({
    required this.hub,
    required this.heartbeatInterval,
    required this.presenceTimeout,
    required this.broadcast,
    required this.onFrame,
    required this.onPing,
    required this.onTimeout,
  });

  /// The hub holding the rooms of the relay.
  final SyncHub hub;

  /// The delay between two beats of the connection.
  final Duration heartbeatInterval;

  /// The delay after which a silent connection is purged.
  final Duration presenceTimeout;

  /// Broadcasts a presence frame to a room.
  final PresenceBroadcaster broadcast;

  /// Sends a frame to the connection.
  final void Function(Map<String, Object?> frame) onFrame;

  /// Sends the `ping` guard to the connection.
  final void Function() onPing;

  /// Closes the connection that stopped beating.
  final Future<void> Function() onTimeout;

  final Map<SyncRoomKey, SyncSubscription> _subscriptions =
      <SyncRoomKey, SyncSubscription>{};

  final Map<SyncRoomKey, StreamSubscription<Map<String, Object?>>> _relays =
      <SyncRoomKey, StreamSubscription<Map<String, Object?>>>{};

  DateTime _lastBeat = DateTime.now();

  Timer? _heartbeat;

  Timer? _purge;

  bool _isClosed = false;

  /// The rooms the connection joined.
  Map<SyncRoomKey, SyncSubscription> get subscriptions =>
      Map<SyncRoomKey, SyncSubscription>.unmodifiable(_subscriptions);

  /// Records a beat of the connection.
  void beat() {
    _lastBeat = DateTime.now();
  }

  /// Starts the heartbeat and the purge.
  ///
  /// The purge looks at the connection every sixth of the timeout: a peer
  /// disappears in less than [presenceTimeout] after it stopped beating, and
  /// the server does not wake up for nothing.
  void start() {
    _heartbeat ??= Timer.periodic(heartbeatInterval, (Timer _) => onPing());
    _purge ??= Timer.periodic(_purgeInterval(), (Timer _) => _purgeIfSilent());
  }

  /// Joins the room [room] for [userId].
  ///
  /// The join is idempotent: a second join on the same room replaces the
  /// first, and the peer is announced once.
  void join(SyncRoomKey room, String userId) {
    if (_isClosed) return;
    final SyncSubscription? previous = _subscriptions[room];
    if (previous != null) hub.leave(previous);
    final StreamSubscription<Map<String, Object?>>? previousRelay = _relays
        .remove(room);
    previousRelay?.cancel();

    final SyncSubscription subscription = hub.join(
      projectId: room.$1,
      docId: room.$2,
      userId: userId,
    );
    _subscriptions[room] = subscription;
    _relays[room] = subscription.frames.listen(onFrame);

    broadcast(
      room.$1,
      room.$2,
      _frame(room.$2, userId, PresenceState.joined),
      except: subscription,
    );
  }

  /// Announces that [userId] moved its caret in the room [room].
  void moved(SyncRoomKey room, String userId, PresenceCursor cursor) {
    if (_isClosed) return;
    final SyncSubscription? subscription = _subscriptions[room];
    if (subscription == null) return;
    broadcast(
      room.$1,
      room.$2,
      _frame(room.$2, userId, PresenceState.cursor, cursor: cursor),
      except: subscription,
    );
  }

  /// Leaves the room [room] and announces the departure of [userId].
  void leave(SyncRoomKey room, String userId) {
    final SyncSubscription? subscription = _subscriptions.remove(room);
    final StreamSubscription<Map<String, Object?>>? relay = _relays.remove(
      room,
    );
    relay?.cancel();
    if (subscription == null) return;
    broadcast(
      room.$1,
      room.$2,
      _frame(room.$2, userId, PresenceState.left),
      except: subscription,
    );
    hub.leave(subscription);
  }

  /// The frame announcing that [userId] is on the document [docId].
  ///
  /// The relay sends it to a newcomer: the peer learns who is already there.
  Map<String, Object?> joinedFrame(String docId, String userId) =>
      _frame(docId, userId, PresenceState.joined);

  /// Leaves every room and announces the departure of [userId].
  void leaveAll(String userId) {
    for (final SyncRoomKey room in _subscriptions.keys.toList(
      growable: false,
    )) {
      leave(room, userId);
    }
  }

  /// Stops the timers and releases the rooms.
  ///
  /// The call is idempotent: the connection may be closed by the purge and
  /// by the client at the same time.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    _purge?.cancel();
    _purge = null;
    for (final SyncSubscription subscription in _subscriptions.values) {
      hub.leave(subscription);
    }
    _subscriptions.clear();
    for (final StreamSubscription<Map<String, Object?>> relay
        in _relays.values) {
      await relay.cancel();
    }
    _relays.clear();
  }

  /// The delay between two looks at the silence of the connection.
  Duration _purgeInterval() {
    final int micros = presenceTimeout.inMicroseconds ~/ 6;
    return Duration(microseconds: micros <= 0 ? 1 : micros);
  }

  /// Purges the connection when it stayed silent for too long.
  void _purgeIfSilent() {
    if (_isClosed) return;
    final Duration silence = DateTime.now().difference(_lastBeat);
    if (silence <= presenceTimeout) return;
    unawaited(onTimeout());
  }

  /// Builds the presence frame of a peer.
  Map<String, Object?> _frame(
    String docId,
    String userId,
    PresenceState state, {
    PresenceCursor? cursor,
  }) {
    final DateTime now = DateTime.now().toUtc();
    return <String, Object?>{
      'type': 'presence',
      'sent_at': now.toIso8601String(),
      'payload': PresenceCodec.encode(
        PresencePeer(
          docId: docId,
          userId: userId,
          state: state,
          cursor: cursor,
          at: now,
        ),
      ),
    };
  }
}
