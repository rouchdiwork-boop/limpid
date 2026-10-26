/// The kind of content held by a [Block].
///
/// The set is closed on purpose: the CRDT engine switches over it
/// exhaustively.
enum BlockType {
  /// A regular paragraph of prose.
  paragraph,

  /// A level 1 heading (book title / part).
  heading1,

  /// A level 2 heading (chapter title).
  heading2,

  /// A level 3 heading (scene title).
  heading3,

  /// An item of an ordered or unordered list.
  listItem,

  /// A block quotation.
  quote,

  /// A preformatted code block.
  code,

  /// An image reference with its caption and alt text.
  image,

  /// A footnote attached to the text.
  footnote,

  /// A scene separator (`* * *`).
  sceneBreak,
}

/// Whether a [BlockType] contributes prose to the word count.
bool isProseBlockType(BlockType type) => switch (type) {
  BlockType.paragraph ||
  BlockType.listItem ||
  BlockType.quote ||
  BlockType.footnote => true,
  BlockType.heading1 ||
  BlockType.heading2 ||
  BlockType.heading3 ||
  BlockType.code ||
  BlockType.image ||
  BlockType.sceneBreak => false,
};

/// The nature of a [Mark] attached to a range of a block.
enum MarkType {
  /// A user comment anchored on a character range.
  comment,

  /// A note produced by the AI assistant.
  aiNote,

  /// A suggestion proposed by the AI assistant.
  aiSuggestion,

  /// A spelling or grammar flag.
  suggestion,

  /// A link to another scene, character or event.
  reference,

  /// A bookmark placed by the author.
  bookmark,
}

/// Whether a mark type is an AI-generated annotation.
bool isAiMarkType(MarkType type) => switch (type) {
  MarkType.aiNote || MarkType.aiSuggestion => true,
  MarkType.comment ||
  MarkType.suggestion ||
  MarkType.reference ||
  MarkType.bookmark => false,
};

/// The editorial pipeline stage of a chapter or scene.
enum ManuscriptStatus {
  /// Not started yet.
  draft,

  /// Actively written.
  writing,

  /// Written but not polished.
  revising,

  /// Frozen, awaiting review.
  review,

  /// Approved for publication.
  published,

  /// Archived, hidden from the active tree.
  archived,
}

/// The role a user holds inside a project.
enum ProjectRole {
  /// Full control, including billing and deletion.
  owner,

  /// Can edit the manuscript.
  coAuthor,

  /// Can only comment.
  betaReader,

  /// Read-only access.
  reader,
}

/// Whether the role is allowed to modify manuscript content.
bool canEditManuscript(ProjectRole role) => switch (role) {
  ProjectRole.owner || ProjectRole.coAuthor => true,
  ProjectRole.betaReader || ProjectRole.reader => false,
};

/// Whether the role is allowed to post comments.
bool canComment(ProjectRole role) => switch (role) {
  ProjectRole.owner || ProjectRole.coAuthor || ProjectRole.betaReader => true,
  ProjectRole.reader => false,
};
