/// The state of a peer on the relay.
///
/// The vocabulary is closed: the relay never invents a state, and the two
/// sides of the connection share it. A peer enters a document, moves its
/// cursor, and leaves it — the state `left` also covers the peers the relay
/// purges because they stopped beating.
enum PresenceState {
  /// The peer entered the document.
  joined,

  /// The peer left the document, or stopped beating.
  left,

  /// The peer moved its cursor.
  cursor;

  /// The wire name of the state.
  String get wireName => switch (this) {
    PresenceState.joined => 'joined',
    PresenceState.left => 'left',
    PresenceState.cursor => 'cursor',
  };

  /// Parses the wire name of a state.
  ///
  /// Returns `null` when the name is unknown: an unknown state is not a
  /// presence, and the relay ignores it rather than guessing.
  static PresenceState? parse(String? raw) {
    if (raw == null) return null;
    for (final PresenceState state in PresenceState.values) {
      if (state.wireName == raw) return state;
    }
    return null;
  }
}

/// The position of the cursor of a peer.
///
/// The position is expressed in the coordinates of the document: the block
/// the caret stands in, and the offset of the caret inside that block. The
/// two together locate the caret without shipping the text of the scene.
final class PresenceCursor {
  /// Creates a cursor position.
  const PresenceCursor({required this.blockId, required this.offset});

  /// The block the caret stands in.
  final String blockId;

  /// The offset of the caret inside the block.
  final int offset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PresenceCursor &&
          other.blockId == blockId &&
          other.offset == offset);

  @override
  int get hashCode => Object.hash(blockId, offset);

  @override
  String toString() => 'PresenceCursor($blockId, $offset)';
}

/// A peer seen on the relay.
///
/// The peer is the **account**, not the connection: the same author on two
/// devices is one peer. The relay is the only authority on the presence: a
/// client never announces that it left, it simply stops beating.
final class PresencePeer {
  /// Creates a peer.
  const PresencePeer({
    required this.docId,
    required this.userId,
    required this.state,
    this.cursor,
    this.displayName,
    this.avatarUrl,
    this.at,
  });

  /// The document the peer is on.
  final String docId;

  /// The account of the peer.
  final String userId;

  /// The state of the peer.
  final PresenceState state;

  /// The position of the caret of the peer, `null` when it did not move.
  final PresenceCursor? cursor;

  /// The name the interface shows, `null` when the relay does not know it.
  final String? displayName;

  /// The avatar of the peer, `null` when the relay does not know it.
  final String? avatarUrl;

  /// The moment the relay produced the frame, `null` when it did not stamp it.
  final DateTime? at;

  /// Returns a copy of this peer with the given fields replaced.
  PresencePeer copyWith({
    PresenceState? state,
    PresenceCursor? cursor,
    String? displayName,
    String? avatarUrl,
    DateTime? at,
  }) {
    return PresencePeer(
      docId: docId,
      userId: userId,
      state: state ?? this.state,
      cursor: cursor ?? this.cursor,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      at: at ?? this.at,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PresencePeer &&
          other.docId == docId &&
          other.userId == userId &&
          other.state == state &&
          other.cursor == cursor &&
          other.displayName == displayName &&
          other.avatarUrl == avatarUrl &&
          other.at == at);

  @override
  int get hashCode =>
      Object.hash(docId, userId, state, cursor, displayName, avatarUrl, at);

  @override
  String toString() => 'PresencePeer($userId, $docId, ${state.wireName})';
}
