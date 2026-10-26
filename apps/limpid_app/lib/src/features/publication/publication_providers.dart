import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';

/// The public page of a book.
///
/// The provider reads the publication repository: the showcase of the server
/// when it answers, the local manuscript when it cannot. A book that is not
/// published has no public page — the provider says so instead of showing an
/// empty shell.
final publicationProvider = FutureProvider.family<Publication, String>((
  Ref ref,
  String projectId,
) async {
  final PublicationRepository repository = ref.watch(
    publicationRepositoryProvider,
  );
  return repository.load(projectId: projectId);
});
