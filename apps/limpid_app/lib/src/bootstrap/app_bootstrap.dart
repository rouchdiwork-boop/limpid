import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/auth_runtime.dart';
import 'package:limpid_app/src/auth/local_auth_store.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// The configuration of the backend.
///
/// The values come from the `--dart-define` flags. The tests build their own
/// configuration to exercise the failure paths.
@immutable
class AppConfig {
  /// Creates the configuration.
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  /// The configuration of the running application.
  static const AppConfig environment = AppConfig(
    supabaseUrl: AppBootstrap.supabaseUrl,
    supabasePublishableKey: AppBootstrap.supabasePublishableKey,
  );

  /// The URL of the Supabase project.
  final String supabaseUrl;

  /// The publishable key of the Supabase project.
  ///
  /// It is the public, publishable key — never the secret key.
  final String supabasePublishableKey;

  /// Whether the configuration points to a Supabase project.
  bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}

/// Prepares the services the application needs before the first frame.
///
/// The Supabase client is only initialised when its URL and its publishable
/// key are provided through `--dart-define`. Without them the application
/// starts in **demo mode**: the authentication screen explains how to
/// configure it and the rest of the interface stays reachable, so that the
/// design can be reviewed on a fresh machine.
///
/// The bootstrap also restores the session of the author: the application
/// never shows the sign-in screen when a session already exists.
abstract final class AppBootstrap {
  /// The Supabase project URL, supplied with `--dart-define=SUPABASE_URL=...`.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// The Supabase publishable key, supplied with
  /// `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`.
  ///
  /// This is the public, publishable key — never the secret key.
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  /// The time the application waits for the authentication service at startup.
  ///
  /// The startup never waits for the service: when it does not answer in time,
  /// the application starts in demo mode.
  static const Duration startupTimeout = Duration(seconds: 8);

  /// Whether the application runs with a real Supabase backend.
  static bool get isSupabaseConfigured =>
      AuthRuntimeHolder.current.mode == AuthMode.supabase;

  /// Runs the bootstrap.
  ///
  /// The bootstrap never throws: a backend that does not answer must not
  /// prevent the application from starting.
  static Future<void> run({AppConfig config = AppConfig.environment}) async {
    if (!config.hasSupabase) {
      debugPrint(
        'Limpid démarre en mode démonstration : SUPABASE_URL et '
        'SUPABASE_PUBLISHABLE_KEY ne sont pas définies.',
      );
      await _useDemoMode();
      return;
    }

    try {
      await sb.Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
        authOptions: const sb.FlutterAuthClientOptions(
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUri: true,
        ),
      ).timeout(startupTimeout);
      final session = await _restoreSession().timeout(startupTimeout);
      AuthRuntimeHolder.set(
        SupabaseAuthRuntime(
          client: sb.Supabase.instance.client,
          session: session,
        ),
      );
    } on Object catch (error) {
      debugPrint(
        'Le service d\'authentification ne répond pas ($error) : '
        'Limpid démarre en mode démonstration.',
      );
      await _useDemoMode();
    }
  }

  /// Restores the session of the author, when there is one.
  static Future<AuthSession?> _restoreSession() async {
    final client = sb.Supabase.instance.client;
    final completer = Completer<AuthSession?>();
    final subscription = client.auth.onAuthStateChange.listen((state) {
      if (!completer.isCompleted) {
        completer.complete(supabaseSession(state.session));
      }
    });
    try {
      return await completer.future;
    } finally {
      await subscription.cancel();
    }
  }

  /// Starts the application without a remote service.
  ///
  /// The local session is restored from the support directory of the
  /// application. When the file system is not reachable, the session is kept
  /// in memory: the application starts, the session is simply not persisted.
  static Future<void> _useDemoMode() async {
    try {
      final store = await FileLocalAuthStore.open();
      final session = (await store.read())?.session;
      AuthRuntimeHolder.set(DemoAuthRuntime(store: store, session: session));
    } on Object catch (error) {
      debugPrint('La session locale ne peut pas être lue ($error).');
      AuthRuntimeHolder.set(DemoAuthRuntime(store: InMemoryLocalAuthStore()));
    }
  }
}
