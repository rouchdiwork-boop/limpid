import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/features/publication/publication_author_books.dart';

/// Les livres que la vitrine publie pour un auteur.
///
/// La page lit le contrat de la publication : la vitrine du serveur quand
/// elle répond, la liste vide quand elle ne répond pas. L'application est
/// hors ligne d'abord : une page d'auteur ne coûte jamais un écran d'erreur.
final authorBooksProvider = FutureProvider.family<List<AuthorBook>, String>((
  Ref ref,
  String authorId,
) async {
  final PublicationRepository repository = ref.watch(
    publicationRepositoryProvider,
  );
  if (repository is AuthorBooksPort) {
    return _publishedBooks(repository, authorId);
  }
  return const <AuthorBook>[];
});

/// Les livres publiés de l'auteur, ou la liste vide.
///
/// Le serveur injoignable et l'auteur qui ne publie aucun livre sont les
/// deux réponses qui rendent la page vide : un lecteur n'a jamais à lire
/// une erreur pour une page de vitrine.
Future<List<AuthorBook>> _publishedBooks(
  AuthorBooksPort repository,
  String authorId,
) async {
  try {
    final List<AuthorBook> books = await repository.listShowcaseBooks(
      authorId: authorId,
    );
    return List<AuthorBook>.unmodifiable(books);
  } on ApiNotFoundException {
    return const <AuthorBook>[];
  } on ApiNetworkException {
    return const <AuthorBook>[];
  } on ApiTimeoutException {
    return const <AuthorBook>[];
  }
}
