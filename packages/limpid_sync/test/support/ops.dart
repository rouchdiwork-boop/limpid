import 'package:limpid_core/limpid_core.dart' hide SyncTransport;

/// Builds the operations of an author, with a Lamport clock.
///
/// The factory is the test-side equivalent of the `SyncEngine` of
/// `limpid_core`: it keeps the clock, and [observe] advances it when a
/// remote operation is received.
final class OpFactory {
  /// Creates a factory for [authorId].
  OpFactory(this.authorId) : _clock = const LamportClock();

  /// The author of the produced operations.
  final AuthorId authorId;

  LamportClock _clock;

  /// The current logical time.
  int get current => _clock.current;

  /// Registers the reception of a remote operation.
  void observe(SyncOp operation) {
    _clock = _clock.receive(operation.lamport);
  }

  /// Builds an insertion.
  InsertBlockOp insertBlock({
    required DocumentId doc,
    required BlockId blockId,
    BlockId? parent,
    OrderKey? order,
    BlockType type = BlockType.paragraph,
    BlockContent content = const TextContent(''),
  }) {
    final tick = _clock.tick();
    _clock = tick;
    return InsertBlockOp(
      doc: doc,
      lamport: tick.current,
      author: authorId,
      blockId: blockId,
      parent: parent,
      order: order ?? OrderKey.initial,
      type: type,
      content: content,
    );
  }

  /// Builds a content update.
  UpdateContentOp updateContent({
    required DocumentId doc,
    required BlockId blockId,
    required BlockContent content,
    ContentBase? base,
  }) {
    final tick = _clock.tick();
    _clock = tick;
    return UpdateContentOp(
      doc: doc,
      lamport: tick.current,
      author: authorId,
      blockId: blockId,
      content: content,
      base: base,
    );
  }

  /// Builds a deletion.
  DeleteBlockOp deleteBlock({
    required DocumentId doc,
    required BlockId blockId,
  }) {
    final tick = _clock.tick();
    _clock = tick;
    return DeleteBlockOp(
      doc: doc,
      lamport: tick.current,
      author: authorId,
      blockId: blockId,
    );
  }

  /// Builds a move.
  MoveBlockOp moveBlock({
    required DocumentId doc,
    required BlockId blockId,
    BlockId? parent,
    OrderKey? order,
  }) {
    final tick = _clock.tick();
    _clock = tick;
    return MoveBlockOp(
      doc: doc,
      lamport: tick.current,
      author: authorId,
      blockId: blockId,
      parent: parent,
      order: order ?? OrderKey.initial,
    );
  }

  /// Builds a metadata write.
  SetMetaOp setMeta({
    required DocumentId doc,
    required String key,
    required String value,
  }) {
    final tick = _clock.tick();
    _clock = tick;
    return SetMetaOp(
      doc: doc,
      lamport: tick.current,
      author: authorId,
      key: key,
      value: value,
    );
  }
}
