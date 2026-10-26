import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/app/limpid_app.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/local_auth_store.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:limpid_app/src/features/auth/screens/sign_in_screen.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_screen.dart';

void main() {
  testWidgets('la session restaurée ne montre pas l\'écran de connexion', (
    tester,
  ) async {
    final repository = DemoAuthRepository(
      store: InMemoryLocalAuthStore(),
      session: const AuthSession(
        userId: 'demo-1',
        email: 'camille@atelier-sable.fr',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const LimpidApp(),
      ),
    );

    // Le routeur lit la session avant la première image : l'écran de
    // connexion ne doit jamais apparaître.
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump();
      expect(find.byType(SignInScreen), findsNothing);
    }

    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('sans session, l\'écran de connexion est affiché', (
    tester,
  ) async {
    final repository = DemoAuthRepository(store: InMemoryLocalAuthStore());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const LimpidApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });
}
