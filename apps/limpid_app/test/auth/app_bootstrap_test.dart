import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/auth/auth_runtime.dart';
import 'package:limpid_app/src/bootstrap/app_bootstrap.dart';

void main() {
  setUp(AuthRuntimeHolder.reset);
  tearDown(AuthRuntimeHolder.reset);

  test('le mode démonstration ouvre une session locale', () async {
    await AppBootstrap.run();

    expect(AppBootstrap.isSupabaseConfigured, isFalse);
    expect(AuthRuntimeHolder.current, isA<DemoAuthRuntime>());
  });

  test(
    'le démarrage ne lève jamais quand le service est injoignable',
    () async {
      // Le client Supabase ne peut pas démarrer dans un environnement sans
      // plugin : l'erreur du SDK est laissée derrière lui par la bibliothèque.
      // L'application, elle, ne doit pas planter.
      await runZonedGuarded(
        () => AppBootstrap.run(
          config: const AppConfig(
            supabaseUrl: 'http://127.0.0.1:1',
            supabasePublishableKey: 'test-publishable-key',
          ),
        ),
        (error, stackTrace) {},
      );

      // L'application démarre quand même, en mode démonstration.
      expect(AppBootstrap.isSupabaseConfigured, isFalse);
      expect(AuthRuntimeHolder.current, isA<DemoAuthRuntime>());
    },
  );
}
