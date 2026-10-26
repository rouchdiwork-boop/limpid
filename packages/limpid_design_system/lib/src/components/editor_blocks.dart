/// The business components of the Limpid design system.
///
/// They cover the vocabulary of the writing studio: scenes, outline,
/// comments, AI suggestions, synchronization, covers, word counts and
/// characters.
///
/// The implementations are split by family to keep every file focused:
/// * [editor_structure] holds the structure of a book (scenes, outline,
///   cover, word count, characters).
/// * [editor_review] holds the collaboration features (comments, AI
///   suggestions, synchronization status).
library;

export 'package:limpid_design_system/src/components/editor_review.dart'
    show
        LimpidAiSuggestionDiff,
        LimpidCommentThread,
        LimpidSyncStatus,
        LimpidSyncStatusPill;
export 'package:limpid_design_system/src/components/editor_structure.dart'
    show
        LimpidCharacterAvatar,
        LimpidCoverPreview,
        LimpidOutlineRow,
        LimpidSceneCard,
        LimpidWordCountMeter;
