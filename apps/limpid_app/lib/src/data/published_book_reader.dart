import 'package:limpid_core/limpid_core.dart';

/// The reading of a published book, whoever the reader is.
///
/// A published book is public: the showcase of the server serves it to a
/// reader who has no account and no manuscript. This optional capability
/// lets the local fallback of the showcase find a published book in the
/// local database, even when the reader is not its author — the reads of
/// the library stay private to the author they belong to.
abstract interface class PublishedBookReader {
  /// The published project of [projectId], `null` when there is none.
  ///
  /// Only a book in the `published` stage is returned: an unpublished
  /// manuscript is never public.
  Future<Project?> findPublishedProject(String projectId);
}
