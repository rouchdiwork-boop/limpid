import 'package:limpid_core/limpid_core.dart';

/// The mark that anchors a discussion on the passage the author selected.
///
/// The mark is an operation of the CRDT: it leaves like every other writing,
/// and the anchor of the discussion follows the text when the block is
/// rewritten.
final class CommentAnchor {
  CommentAnchor._(this.markId, this.operation);

  /// The generator of the identifiers of the marks.
  static final UlidGenerator _ids = UlidGenerator();

  /// Creates the anchor of a discussion.
  ///
  /// The mark is posed through the **synchronisation engine**: the engine
  /// stamps the operation with the Lamport timestamp of its writing and
  /// builds the operation the server understands.
  ///
  /// The timestamp is more recent than every version of the block: the range
  /// of the anchor is then computed on the text the author was reading, and
  /// the recalculation of the kernel moves it when the block is rewritten.
  factory CommentAnchor.of({
    required CrdtDocument document,
    required DocumentId documentId,
    required AuthorId author,
    required int lamport,
    required BlockId blockId,
    required MarkRange range,
    required String body,
  }) {
    final MarkId markId = MarkId(_ids.generate().value);
    final SyncEngine engine = SyncEngine(
      documentId: documentId,
      authorId: author,
      document: document,
      clock: LamportClock(lamport),
    );
    final SyncEngine marked = engine.addMark(
      markId: markId,
      blockId: blockId,
      type: MarkType.comment,
      range: range,
      body: body,
    );
    final AddMarkOp operation = marked.pendingOperations.single as AddMarkOp;
    return CommentAnchor._(markId, operation);
  }

  /// The identifier of the mark.
  final MarkId markId;

  /// The operation that poses the mark.
  final AddMarkOp operation;

  @override
  String toString() => 'CommentAnchor($markId)';
}
