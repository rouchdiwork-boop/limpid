import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_app/src/features/projects/project_cover.dart';
import 'package:limpid_app/src/features/projects/project_metrics.dart';
import 'package:limpid_app/src/features/publication/publication_author_books.dart';
import 'package:limpid_app/src/features/publication/publication_author_providers.dart';
import 'package:limpid_app/src/features/publication/publication_routes.dart';
import 'package:limpid_app/src/features/publication/publication_states.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La largeur de la couverture d'un livre, sur la page d'un auteur.
const double authorBookCoverWidth = 96;

/// La clé de la liste des livres d'un auteur.
const Key authorBooksKey = Key('author-books');

/// La clé de la couverture du livre [bookId], sur la page d'un auteur.
///
/// La couverture porte le titre du livre : la clé désigne la couverture
/// seule, pour que le titre reste trouvable une fois.
Key authorBookCoverKeyOf(String bookId) =>
    ValueKey<String>('author-book-cover-$bookId');

/// La clé du titre du livre [bookId], sur la page d'un auteur.
Key authorBookTitleKeyOf(String bookId) =>
    ValueKey<String>('author-book-title-$bookId');

/// La page publique d'un auteur.
///
/// Elle liste les livres publiés de l'auteur : la couverture, le titre, le
/// résumé et le nombre de mots de chaque livre, et un chemin vers la vitrine
/// du livre. La page dégrade vers son état vide quand le serveur ne publie
/// rien : l'application est hors ligne d'abord.
class PublicationAuthorScreen extends ConsumerWidget {
  /// Crée la page publique d'un auteur.
  const PublicationAuthorScreen({
    required this.authorId,
    this.onOpenBook,
    super.key,
  });

  /// L'identifiant de l'auteur.
  final String authorId;

  /// Appelé quand le lecteur demande la vitrine d'un livre.
  ///
  /// Quand elle est nulle, la page va vers la route de vitrine de
  /// l'application.
  final ValueChanged<String>? onOpenBook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AuthorBook>> books = ref.watch(
      authorBooksProvider(authorId),
    );

    return Scaffold(
      body: SafeArea(
        child: books.when(
          loading: () => const PublicationLoading(),
          error: (Object error, StackTrace stackTrace) => PublicationFailure(
            onRetry: () => ref.invalidate(authorBooksProvider(authorId)),
          ),
          data: (List<AuthorBook> published) {
            if (published.isEmpty) return const PublicationAuthorEmpty();
            return _AuthorBooksView(books: published, onOpenBook: onOpenBook);
          },
        ),
      ),
    );
  }
}

/// La liste des livres publiés d'un auteur.
class _AuthorBooksView extends StatelessWidget {
  /// Crée la liste des livres d'un auteur.
  const _AuthorBooksView({required this.books, this.onOpenBook});

  /// Les livres publiés de l'auteur.
  final List<AuthorBook> books;

  /// Appelé quand le lecteur demande la vitrine d'un livre.
  final ValueChanged<String>? onOpenBook;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return ListView(
      key: authorBooksKey,
      padding: EdgeInsets.all(scope.spacing.space24),
      children: <Widget>[
        Text(
          strings.publicationAuthorTitle,
          style: textTheme.headlineMedium?.copyWith(
            color: scope.colors.fgDefault,
            fontFamily: LimpidFontFamily.display,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: scope.spacing.space8),
        Text(
          strings.publicationAuthorBookCount(books.length),
          style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space24),
        for (final AuthorBook book in books) ...<Widget>[
          _AuthorBookTile(book: book, onOpenBook: onOpenBook),
          SizedBox(height: scope.spacing.space16),
        ],
      ],
    );
  }
}

/// La fiche d'un livre publié : sa couverture et sa page de vitrine.
class _AuthorBookTile extends StatelessWidget {
  /// Crée la fiche d'un livre publié.
  const _AuthorBookTile({required this.book, this.onOpenBook});

  /// Le livre affiché par la fiche.
  final AuthorBook book;

  /// Appelé quand le lecteur demande la vitrine du livre.
  final ValueChanged<String>? onOpenBook;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return LimpidCard(
      onTap: () => _openBook(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ProjectCover(
            key: authorBookCoverKeyOf(book.id),
            title: book.title,
            author: '',
            seed: coverSeedOf(book.id),
            width: authorBookCoverWidth,
          ),
          SizedBox(width: scope.spacing.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  book.title,
                  key: authorBookTitleKeyOf(book.id),
                  style: textTheme.titleMedium?.copyWith(
                    color: scope.colors.fgDefault,
                    fontFamily: LimpidFontFamily.display,
                  ),
                ),
                if (book.synopsis.isNotEmpty) ...<Widget>[
                  SizedBox(height: scope.spacing.space8),
                  Text(
                    book.synopsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scope.colors.fgMuted,
                      fontFamily: LimpidFontFamily.manuscript,
                      height: 1.6,
                    ),
                  ),
                ],
                SizedBox(height: scope.spacing.space8),
                Text(
                  strings.libraryWords(formatCount(book.wordCount)),
                  style: textTheme.bodySmall?.copyWith(
                    color: scope.colors.fgSubtle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ouvre la vitrine du livre.
  void _openBook(BuildContext context) {
    final ValueChanged<String>? callback = onOpenBook;
    if (callback != null) {
      callback(book.id);
      return;
    }
    context.go(PublicationRoutes.showcase(book.id));
  }
}

/// L'état vide de la page d'un auteur.
///
/// Un auteur qui ne publie aucun livre n'a pas de page : l'état le dit
/// explicitement, plutôt que d'afficher une coquille vide qui ressemble à
/// un auteur sans livres.
class PublicationAuthorEmpty extends StatelessWidget {
  /// Crée l'état vide de la page d'un auteur.
  const PublicationAuthorEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scope.spacing.space48),
      child: LimpidEmptyState(
        title: strings.publicationAuthorEmpty,
        message: strings.publicationAuthorEmptyMessage,
        icon: LimpidIcons.globe,
      ),
    );
  }
}
