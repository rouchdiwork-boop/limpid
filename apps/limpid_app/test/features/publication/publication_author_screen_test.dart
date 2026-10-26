import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/features/projects/project_cover.dart';
import 'package:limpid_app/src/features/publication/publication_author_books.dart';
import 'package:limpid_app/src/features/publication/publication_author_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Le titre du premier livre publié par le serveur.
const String firstTitle = 'Les Heures de Cendre';

/// Le résumé du premier livre publié par le serveur.
const String firstSynopsis =
    'Dans un village de pêcheurs qui ne compte plus ses morts.';

/// Le titre du second livre publié par le serveur.
const String secondTitle = 'Carnets de dune';

void main() {
  /// Donne au test une fenêtre assez grande pour la mise en page large.
  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Les livres que le serveur publie.
  List<AuthorBook> publishedBooks() {
    return <AuthorBook>[
      const AuthorBook(
        id: 'heures',
        title: firstTitle,
        synopsis: firstSynopsis,
        wordCount: 4300,
      ),
      const AuthorBook(
        id: 'dune',
        title: secondTitle,
        synopsis: 'Les carnets que le vent emporte sous les dunes.',
        wordCount: 1200,
      ),
    ];
  }

  /// Enveloppe l'écran dans les dépendances et le thème qu'il lui faut.
  Widget harness({
    required Widget child,
    required FakeAuthorBooksRepository publications,
  }) {
    return ProviderScope(
      overrides: [
        publicationRepositoryProvider.overrideWithValue(publications),
      ],
      child: MaterialApp(
        theme: LimpidTheme.of(LimpidThemeVariant.paper),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  /// Les chaînes de l'interface, lues sur l'écran rendu.
  AppLocalizations stringsOf(WidgetTester tester) {
    return AppLocalizations.of(
      tester.element(find.byType(PublicationAuthorScreen)),
    );
  }

  group('la page d’un auteur', () {
    testWidgets('liste les livres que le serveur publie', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      final FakeAuthorBooksRepository publications = FakeAuthorBooksRepository(
        books: publishedBooks(),
      );

      await tester.pumpWidget(
        harness(
          child: const PublicationAuthorScreen(authorId: 'auteur-1'),
          publications: publications,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.byKey(authorBookTitleKeyOf('heures')), findsOneWidget);
      expect(find.byKey(authorBookTitleKeyOf('dune')), findsOneWidget);
      expect(find.text(firstSynopsis), findsOneWidget);
      expect(find.byKey(authorBookCoverKeyOf('heures')), findsOneWidget);
      expect(find.byKey(authorBookCoverKeyOf('dune')), findsOneWidget);
      expect(find.text(strings.libraryWords('4 300')), findsOneWidget);
      expect(publications.calls, 1);
    });

    testWidgets('ouvre la vitrine du livre', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      final FakeAuthorBooksRepository publications = FakeAuthorBooksRepository(
        books: publishedBooks(),
      );
      final List<String> opened = <String>[];

      await tester.pumpWidget(
        harness(
          child: PublicationAuthorScreen(
            authorId: 'auteur-1',
            onOpenBook: opened.add,
          ),
          publications: publications,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(authorBookTitleKeyOf('heures')));
      await tester.pumpAndSettle();

      expect(opened, <String>['heures']);
    });

    testWidgets('montre l’état vide quand le serveur ne publie rien', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final FakeAuthorBooksRepository publications =
          FakeAuthorBooksRepository();

      await tester.pumpWidget(
        harness(
          child: const PublicationAuthorScreen(authorId: 'auteur-1'),
          publications: publications,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.text(strings.publicationAuthorEmpty), findsOneWidget);
      expect(find.text(strings.errorGeneric), findsNothing);
      expect(find.byType(ProjectCover), findsNothing);
    });

    testWidgets(
      'montre l’état vide et jamais un écran d’erreur quand le serveur est injoignable',
      (tester) async {
        useSurface(tester, const Size(1440, 1100));
        final FakeAuthorBooksRepository publications =
            FakeAuthorBooksRepository()
              ..error = const ApiNetworkException('the API is unreachable');

        await tester.pumpWidget(
          harness(
            child: const PublicationAuthorScreen(authorId: 'auteur-1'),
            publications: publications,
          ),
        );
        await tester.pumpAndSettle();

        final AppLocalizations strings = stringsOf(tester);
        expect(find.text(strings.publicationAuthorEmpty), findsOneWidget);
        expect(find.text(strings.errorGeneric), findsNothing);
        expect(find.text(strings.actionRetry), findsNothing);
      },
    );
  });
}

/// Un dépôt de vitrine que le test pilote à la main.
///
/// Le dépôt tient les livres que le serveur publie, et l'erreur que la
/// lecture doit lever : la page d'un auteur ne doit jamais montrer un
/// écran d'erreur quand le serveur est injoignable.
final class FakeAuthorBooksRepository
    implements PublicationRepository, AuthorBooksPort {
  /// Crée un dépôt servant [books].
  FakeAuthorBooksRepository({this.books = const <AuthorBook>[]});

  /// Les livres que le serveur publie.
  List<AuthorBook> books;

  /// L'erreur que la lecture lève, quand elle est posée.
  Object? error;

  /// Le nombre de fois que la page a demandé les livres.
  int calls = 0;

  @override
  Future<List<AuthorBook>> listShowcaseBooks({required String authorId}) async {
    calls += 1;
    final Object? failure = error;
    if (failure != null) throw failure;
    return books;
  }

  @override
  Future<Publication> load({required String projectId}) async {
    return UnknownBook(projectId: projectId);
  }
}
