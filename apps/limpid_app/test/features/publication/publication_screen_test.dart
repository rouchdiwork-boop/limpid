import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/data/api_publication_repository.dart';
import 'package:limpid_app/src/data/local_publication_repository.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/features/projects/project_cover.dart';
import 'package:limpid_app/src/features/publication/publication_reader.dart';
import 'package:limpid_app/src/features/publication/publication_screen.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';
import 'sale/fakes.dart';

/// The synopsis of the published book of the tests.
const String bookSynopsis =
    'Dans un village de pêcheurs qui ne compte plus ses morts.';

/// The first paragraph of the first scene of the book.
const String firstExcerpt = 'La cloche sonna à quatre heures douze.';

/// The second paragraph of the first scene of the book.
const String secondParagraph = 'Le sel avait formé sur les vitres une croûte.';

/// The excerpt of the second scene of the book.
const String otherExcerpt = "C'était écrit dans le registre municipal.";

void main() {
  /// Gives the test a viewport large enough for the desktop layout.
  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The published book the public page displays.
  FakePublicationRepository publishedBook() {
    return FakePublicationRepository(
      projects: <Project>[
        fakePublicationProject(
          id: 'heures',
          title: 'Les Heures de Cendre',
          synopsis: bookSynopsis,
        ),
      ],
      chapters: <String, List<Chapter>>{
        'heures': <Chapter>[
          fakePublicationChapter(
            id: 'c1',
            title: 'Le sel',
            synopsis: 'La cloche sonne encore.',
            sceneIds: <String>['s1', 's2'],
          ),
        ],
      },
      scenes: <String, List<Scene>>{
        'c1': <Scene>[
          fakePublicationScene(
            id: 's1',
            chapterId: 'c1',
            title: "L'aube",
            wordCount: 120,
          ),
          fakePublicationScene(
            id: 's2',
            chapterId: 'c1',
            title: 'Le registre',
            wordCount: 90,
          ),
        ],
      },
      documents: <String, CrdtDocument>{
        'document-s1': fakePublicationDocument(
          documentId: 'document-s1',
          paragraphs: <String>[firstExcerpt, secondParagraph],
        ),
        'document-s2': fakePublicationDocument(
          documentId: 'document-s2',
          paragraphs: <String>[otherExcerpt],
        ),
      },
    );
  }

  /// Wraps the screen in the providers and the theme it needs.
  Widget harness({
    required Widget child,
    FakePublicationRepository? manuscripts,
    PublicationRepository? publications,
    BookSaleRepository? sales,
  }) {
    return ProviderScope(
      overrides: [
        manuscriptRepositoryProvider.overrideWithValue(
          manuscripts ?? FakePublicationRepository(),
        ),
        if (publications != null)
          publicationRepositoryProvider.overrideWithValue(publications),
        bookSaleRepositoryProvider.overrideWithValue(
          sales ?? FakeBookSaleRepository(),
        ),
      ],
      child: MaterialApp(
        theme: LimpidTheme.of(LimpidThemeVariant.paper),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  /// The strings of the interface, read from the rendered screen.
  AppLocalizations stringsOf(WidgetTester tester) {
    return AppLocalizations.of(tester.element(find.byType(PublicationScreen)));
  }

  group('the public page of a book', () {
    testWidgets('shows the title, the synopsis and the cover', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      await tester.pumpWidget(
        harness(
          child: const PublicationScreen(projectId: 'heures'),
          manuscripts: publishedBook(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(publicationTitleKey), findsOneWidget);
      expect(find.text('Les Heures de Cendre'), findsWidgets);
      expect(find.text(bookSynopsis), findsOneWidget);
      expect(find.byType(ProjectCover), findsOneWidget);
    });

    testWidgets('lists the chapters of the book', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      await tester.pumpWidget(
        harness(
          child: const PublicationScreen(projectId: 'heures'),
          manuscripts: publishedBook(),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.text(strings.publicationContents), findsOneWidget);
      expect(find.text('Le sel'), findsOneWidget);
      expect(find.text('La cloche sonne encore.'), findsOneWidget);
    });

    testWidgets('offers to buy the book when it is for sale', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      final List<String> opened = <String>[];

      await tester.pumpWidget(
        harness(
          child: PublicationScreen(projectId: 'heures', onOpenSale: opened.add),
          manuscripts: publishedBook(),
          sales: FakeBookSaleRepository(sale: fakeBookSale()),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.byKey(publicationBuyKey), findsOneWidget);
      expect(find.text(strings.saleBuy), findsOneWidget);

      await tester.tap(find.byKey(publicationBuyKey));
      await tester.pumpAndSettle();

      expect(opened, <String>['heures']);
    });

    testWidgets('does not offer to buy a book that is not for sale', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));

      await tester.pumpWidget(
        harness(
          child: const PublicationScreen(projectId: 'heures'),
          manuscripts: publishedBook(),
          sales: FakeBookSaleRepository(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(publicationBuyKey), findsNothing);
    });

    testWidgets('shows the excerpt of a scene and never its whole text', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      await tester.pumpWidget(
        harness(
          child: const PublicationScreen(projectId: 'heures'),
          manuscripts: publishedBook(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(firstExcerpt), findsOneWidget);
      expect(find.text(secondParagraph), findsNothing);
      expect(find.text(otherExcerpt), findsOneWidget);
    });

    testWidgets('shows the state of a book that is not published', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final FakePublicationRepository manuscripts = FakePublicationRepository(
        projects: <Project>[
          fakePublicationProject(
            id: 'brouillon',
            title: 'Carnets de dune',
            status: ManuscriptStatus.draft,
          ),
        ],
      );

      await tester.pumpWidget(
        harness(
          child: const PublicationScreen(projectId: 'brouillon'),
          manuscripts: manuscripts,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.text(strings.publicationNotPublished), findsOneWidget);
      expect(find.text(strings.projectStatusDraft), findsOneWidget);
      expect(find.text(strings.projectStatusPublished), findsNothing);
      expect(find.text('Carnets de dune'), findsNothing);
    });

    testWidgets('shows the error state when the repository fails', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final FakePublicationRepository manuscripts = FakePublicationRepository()
        ..error = StateError('the database is closed');

      await tester.pumpWidget(
        harness(
          child: const PublicationScreen(projectId: 'heures'),
          manuscripts: manuscripts,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = stringsOf(tester);
      expect(find.text(strings.errorGeneric), findsOneWidget);
      expect(find.text(strings.actionRetry), findsOneWidget);
    });

    testWidgets('is a single column under 900 pixels', (tester) async {
      useSurface(tester, const Size(600, 1100));
      await tester.pumpWidget(
        harness(
          child: const PublicationScreen(projectId: 'heures'),
          manuscripts: publishedBook(),
        ),
      );
      await tester.pumpAndSettle();

      final Offset cover = tester.getTopLeft(find.byKey(publicationCoverKey));
      final Offset summary = tester.getTopLeft(
        find.byKey(publicationSummaryKey),
      );
      final Offset table = tester.getTopLeft(
        find.byKey(publicationTableOfContentsKey),
      );

      expect(cover.dx, summary.dx);
      expect(cover.dy, lessThan(summary.dy));
      expect(table.dx, summary.dx);
      expect(table.dy, greaterThan(summary.dy));
    });

    testWidgets('puts the cover on the left above 900 pixels', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      await tester.pumpWidget(
        harness(
          child: const PublicationScreen(projectId: 'heures'),
          manuscripts: publishedBook(),
        ),
      );
      await tester.pumpAndSettle();

      final Offset cover = tester.getTopLeft(find.byKey(publicationCoverKey));
      final Offset summary = tester.getTopLeft(
        find.byKey(publicationSummaryKey),
      );
      final Offset table = tester.getTopLeft(
        find.byKey(publicationTableOfContentsKey),
      );

      expect(cover.dx, lessThan(summary.dx));
      expect(cover.dy, summary.dy);
      expect(table.dx, greaterThan(cover.dx));
    });
  });

  group('the reading page of a book', () {
    testWidgets('shows the chapters and their excerpts', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      await tester.pumpWidget(
        harness(
          child: const PublicationReaderScreen(projectId: 'heures'),
          manuscripts: publishedBook(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Le sel'), findsOneWidget);
      expect(find.text(firstExcerpt), findsOneWidget);
      expect(find.text(secondParagraph), findsNothing);
      expect(find.text(otherExcerpt), findsOneWidget);
    });

    testWidgets('shows the state of a book that is not published', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final FakePublicationRepository manuscripts = FakePublicationRepository(
        projects: <Project>[
          fakePublicationProject(
            id: 'brouillon',
            title: 'Carnets de dune',
            status: ManuscriptStatus.writing,
          ),
        ],
      );

      await tester.pumpWidget(
        harness(
          child: const PublicationReaderScreen(projectId: 'brouillon'),
          manuscripts: manuscripts,
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = AppLocalizations.of(
        tester.element(find.byType(PublicationReaderScreen)),
      );
      expect(find.text(strings.publicationNotPublished), findsOneWidget);
      expect(find.text(strings.projectStatusWriting), findsOneWidget);
    });
  });

  group('the page served by the showcase', () {
    testWidgets('shows the book published by the server', (tester) async {
      useSurface(tester, const Size(1440, 1100));
      final FakePublicationPageRepository publications =
          FakePublicationPageRepository(
            publication: const PublishedBook(
              project: Project(
                id: ProjectId('heures'),
                ownerId: kPublicBookAuthorId,
                title: 'Les Heures de Cendre',
                synopsis: bookSynopsis,
                status: ManuscriptStatus.published,
                order: OrderKey.initial,
              ),
              chapters: <PublicationChapter>[],
            ),
          );

      await tester.pumpWidget(
        harness(
          child: const PublicationScreen(projectId: 'heures'),
          publications: publications,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Les Heures de Cendre'), findsWidgets);
      expect(publications.calls, 1);
    });

    testWidgets('falls back to the local page when the server is down', (
      tester,
    ) async {
      useSurface(tester, const Size(1440, 1100));
      final FakePublicationRepository manuscripts = publishedBook();
      final PublicationRepository publications = ApiPublicationRepository(
        client: ApiClient(
          baseUrl: Uri.parse('https://api.test'),
          client: MockClient(
            (http.Request request) async =>
                throw http.ClientException('the API is unreachable'),
          ),
        ),
        fallback: LocalPublicationRepository(manuscript: manuscripts),
      );

      await tester.pumpWidget(
        harness(
          child: const PublicationScreen(projectId: 'heures'),
          manuscripts: manuscripts,
          publications: publications,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Les Heures de Cendre'), findsWidgets);
      expect(find.text(firstExcerpt), findsOneWidget);
    });
  });

  group('the excerpt of a scene', () {
    test('is the first paragraph of the scene', () {
      final CrdtDocument document = fakePublicationDocument(
        documentId: 'document-x',
        paragraphs: <String>['Premier paragraphe.', 'Second paragraphe.'],
      );

      expect(excerptOf(document), 'Premier paragraphe.');
    });

    test('is empty when the scene was never written', () {
      final CrdtDocument document = fakePublicationDocument(
        documentId: 'document-vide',
        paragraphs: const <String>[],
      );

      expect(excerptOf(document), isEmpty);
    });

    test('is shortened on a word boundary', () {
      final String long = List<String>.filled(120, 'Mot').join(' ');

      final String excerpt = truncateExcerpt(long);

      expect(excerpt.length, lessThanOrEqualTo(maxExcerptLength + 1));
      expect(excerpt, endsWith('Mot$excerptEllipsis'));
    });
  });
}
