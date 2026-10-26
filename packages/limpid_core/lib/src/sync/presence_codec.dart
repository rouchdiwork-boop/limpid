import 'presence.dart';

/// The wire format of the presence frames of the relay.
///
/// The codec is shared by the two sides of the connection: the relay writes
/// the frames, the clients read them. A frame it cannot read is **ignored**,
/// never fatal: a malformed presence must not take the operations of the
/// document down with it.
final class PresenceCodec {
  const PresenceCodec._();

  /// Encodes [peer] into the payload of a presence frame.
  ///
  /// The payload is flat: the relay only transmits, it never nests the
  /// presence inside another object.
  static Map<String, Object?> encode(PresencePeer peer) {
    return <String, Object?>{
      'doc_id': peer.docId,
      'user_id': peer.userId,
      'state': peer.state.wireName,
      if (peer.cursor != null)
        'cursor': <String, Object?>{
          'block_id': peer.cursor!.blockId,
          'offset': peer.cursor!.offset,
        },
      if (peer.displayName != null) 'display_name': peer.displayName,
      if (peer.avatarUrl != null) 'avatar_url': peer.avatarUrl,
      if (peer.at != null) 'at': peer.at!.toUtc().toIso8601String(),
    };
  }

  /// Decodes the payload of a presence frame.
  ///
  /// Returns `null` when the payload does not describe a presence: the
  /// document and the account are mandatory, and the state must be one of
  /// the known states.
  static PresencePeer? decode(Map<String, Object?> json) {
    final String? docId = _string(json['doc_id']);
    final String? userId = _string(json['user_id']);
    if (docId == null || userId == null) return null;
    final PresenceState? state = PresenceState.parse(_string(json['state']));
    if (state == null) return null;

    return PresencePeer(
      docId: docId,
      userId: userId,
      state: state,
      cursor: _decodeCursor(json['cursor']),
      displayName: _string(json['display_name']),
      avatarUrl: _string(json['avatar_url']),
      at: _date(json['at']),
    );
  }

  /// Decodes the position of the caret.
  static PresenceCursor? _decodeCursor(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final String? blockId = _string(raw['block_id']);
    final Object? offset = raw['offset'];
    if (blockId == null || offset is! int) return null;
    return PresenceCursor(blockId: blockId, offset: offset);
  }

  /// Reads a string, `null` when the value is absent or of another type.
  static String? _string(Object? raw) => raw is String ? raw : null;

  /// Reads a timestamp, `null` when the value is absent or unreadable.
  static DateTime? _date(Object? raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }
}
