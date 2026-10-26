import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/demo_auth_repository.dart';
import 'package:limpid_app/src/auth/local_auth_store.dart';

void main() {
  group('mode démonstration', () {
    test('la session survit à la réouverture du dépôt de session', () async {
      final store = InMemoryLocalAuthStore();
      final repository = DemoAuthRepository(store: store);
      await repository.sendMagicLink(
        'camille@atelier-sable.fr',
        authorName: 'Camille',
      );

      // L'application redémarre : le dépôt de session est rouvert.
      final reopened = DemoAuthRepository(
        store: store,
        session: (await store.read())?.session,
      );
      final session = await reopened.watchSession().first;

      expect(session, isNotNull);
      expect(session!.email, 'camille@atelier-sable.fr');
      expect(session.authorName, 'Camille');
    });

    test(
      "l'identifiant d'auteur local est stable d'une session à l'autre",
      () async {
        final store = InMemoryLocalAuthStore();
        final repository = DemoAuthRepository(store: store);
        await repository.sendMagicLink('camille@atelier-sable.fr');
        final first = await repository.watchSession().first;

        await repository.signOut();
        await repository.sendMagicLink('camille@atelier-sable.fr');
        final second = await repository.watchSession().first;

        expect(first!.userId, isNotEmpty);
        expect(second!.userId, first.userId);
      },
    );

    test('la déconnexion efface la session persistée', () async {
      final store = InMemoryLocalAuthStore();
      final repository = DemoAuthRepository(store: store);
      await repository.sendMagicLink('camille@atelier-sable.fr');
      expect((await store.read())?.session, isNotNull);

      await repository.signOut();

      expect((await store.read())?.session, isNull);
      final reopened = DemoAuthRepository(
        store: store,
        session: (await store.read())?.session,
      );
      expect(await reopened.watchSession().first, isNull);
    });

    test('la session est rejouée de façon synchrone', () async {
      final repository = DemoAuthRepository(
        store: InMemoryLocalAuthStore(),
        session: const AuthSession(
          userId: 'demo-1',
          email: 'camille@atelier-sable.fr',
        ),
      );

      AuthSession? received;
      repository.watchSession().listen((session) => received = session);

      // Le routeur lit la session avant la première image : le rejeu ne peut
      // pas attendre un tour de boucle.
      expect(received, isNotNull);
      expect(received!.email, 'camille@atelier-sable.fr');
    });

    test('une adresse invalide est refusée', () async {
      final repository = DemoAuthRepository(store: InMemoryLocalAuthStore());

      await expectLater(
        repository.sendMagicLink('pas-une-adresse'),
        throwsA(isA<InvalidEmailException>()),
      );
    });
  });
}
