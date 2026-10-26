import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/src/app/limpid_app.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/auth/local_auth_store.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/publication/publication_routes.dart';
import 'package:limpid_app/src/features/revision/history/history_routes.dart';

import '../features/publication/fakes.dart';

void main() {
  group('the routes of the application', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            DemoAuthRepository(store: InMemoryLocalAuthStore()),
          ),
          manuscriptRepositoryProvider.overrideWithValue(
            FakePublicationRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    testWidgets('the public page of a book is reachable without a session', (
      tester,
    ) async {
      final GoRouter router = await _pumpApplication(tester, container);

      router.go(PublicationRoutes.showcase('livre-1'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/vitrine/livre-1',
      );
    });

    testWidgets('the reading page of a book is reachable without a session', (
      tester,
    ) async {
      final GoRouter router = await _pumpApplication(tester, container);

      router.go(PublicationRoutes.reader('livre-1'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/lire/livre-1',
      );
    });

    testWidgets('the public page of an author is reachable without a session', (
      tester,
    ) async {
      final GoRouter router = await _pumpApplication(tester, container);

      router.go(PublicationRoutes.author('auteur-1'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/auteur/auteur-1',
      );
    });

    testWidgets('the studio of an author asks for a session', (tester) async {
      final GoRouter router = await _pumpApplication(tester, container);

      router.go(AppRoutes.dashboard);
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.signIn,
      );
    });

    testWidgets('the public page of a book is not a page of the studio', (
      tester,
    ) async {
      // The showcase lives outside the shell of the application: a reader
      // opens a page, not the studio of an author.
      expect(PublicationRoutes.showcasePattern, startsWith('/vitrine/'));
      expect(PublicationRoutes.readerPattern, startsWith('/lire/'));
      expect(PublicationRoutes.showcase('a'), startsWith('/vitrine/'));
      expect(PublicationRoutes.reader('a'), startsWith('/lire/'));
    });

    test('la recherche est une page de la bibliotheque', () {
      expect(AppRoutes.search, '/bibliotheque/recherche');
      expect(AppRoutes.searchSegment, 'recherche');
    });

    test('l historique porte sur un document', () {
      expect(HistoryRoutes.detail('doc-1'), '/documents/doc-1/historique');
      expect(HistoryRoutes.detailPattern, startsWith('/documents/'));
    });
  });
}

/// Pumps the application and returns its router.
///
/// The router only builds its configuration when it is attached to a widget
/// tree: a router alone answers an empty path.
Future<GoRouter> _pumpApplication(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const LimpidApp()),
  );
  await tester.pumpAndSettle();
  return container.read(appRouterProvider);
}
