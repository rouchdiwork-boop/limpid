import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_quill/limpid_quill.dart';

/// The number of words of the prose of a document.
///
/// The tombstones are ignored: a deleted block is not part of the manuscript
/// any more. The rules of `limpid_core` decide what counts as prose, so the
/// client and the server agree on the length of a book.
int wordCountOf(CrdtDocument document) {
  return WordCount.ofBlocks(
    document.blocks.where((Block block) => !block.deleted),
  );
}

/// The reading time of a manuscript, in minutes.
///
/// A manuscript that holds at least one word always takes at least one
/// minute: a scene of three words is not read in zero minute.
int readingMinutesOf(int wordCount) {
  if (wordCount <= 0) {
    return 0;
  }
  final Duration duration = const ReadingTimeEstimator().estimate(wordCount);
  final int minutes = (duration.inSeconds / 60).ceil();
  return minutes < 1 ? 1 : minutes;
}

/// The editor blocks of a document.
///
/// The blocks keep the identifiers and the fractional indices of the CRDT, so
/// that the operations produced by the editor target the very blocks the
/// repository stores.
List<SceneBlock> sceneBlocksOf(CrdtDocument document) {
  return List<SceneBlock>.unmodifiable(
    document.blocks
        .where((Block block) => !block.deleted)
        .map(
          (Block block) => SceneBlock(
            id: block.id,
            type: block.type,
            content: block.content,
            order: block.order,
            parent: block.parent,
          ),
        ),
  );
}

/// The highest Lamport timestamp carried by a document.
///
/// The metadata counts too : a scene that holds only its title has already
/// been written, and the first line the author types must not reuse its
/// timestamp. The CRDT identifies an operation by its document, its Lamport
/// timestamp and its author : a reused timestamp would make the new
/// operation look like the old one, and the CRDT would drop it.
int lamportOf(CrdtDocument document) {
  int lamport = 0;
  for (final Block block in document.blocks) {
    if (block.lamport > lamport) {
      lamport = block.lamport;
    }
  }
  for (final MetaEntry entry in document.metaEntries.values) {
    if (entry.lamport > lamport) {
      lamport = entry.lamport;
    }
  }
  return lamport;
}
