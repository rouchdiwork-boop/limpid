import 'package:flutter/foundation.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/local_auth_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// The authentication mode of the application.
enum AuthMode {
  /// The application runs without a remote service: the session is local.
  demo,

  /// The application runs with a Supabase backend.
  supabase,
}

/// The authentication state resolved before the first frame.
@immutable
sealed class AuthRuntime {
  /// Creates the runtime.
  const AuthRuntime({required this.session});

  /// The session restored before the first frame, `null` when there is none.
  final AuthSession? session;

  /// The mode of the runtime.
  AuthMode get mode;
}

/// The runtime of the demonstration mode.
final class DemoAuthRuntime extends AuthRuntime {
  /// Creates the runtime.
  const DemoAuthRuntime({required this.store, super.session});

  /// The store that persists the local session.
  final LocalAuthStore store;

  @override
  AuthMode get mode => AuthMode.demo;
}

/// The runtime backed by Supabase.
final class SupabaseAuthRuntime extends AuthRuntime {
  /// Creates the runtime.
  const SupabaseAuthRuntime({required this.client, super.session});

  /// The client of the Supabase project.
  final sb.SupabaseClient client;

  @override
  AuthMode get mode => AuthMode.supabase;
}

/// Holds the runtime resolved by the bootstrap.
///
/// The bootstrap runs before the first frame: the providers read the runtime
/// it resolves, so that the session is known before the router decides where
/// to send the author.
abstract final class AuthRuntimeHolder {
  static AuthRuntime? _current;

  static final AuthRuntime _fallback = DemoAuthRuntime(
    store: InMemoryLocalAuthStore(),
  );

  /// The runtime of the application.
  ///
  /// Before the bootstrap runs — in the tests, for instance — the application
  /// runs in demonstration mode, without a persisted session.
  static AuthRuntime get current => _current ?? _fallback;

  /// Sets the runtime of the application.
  static void set(AuthRuntime runtime) {
    _current = runtime;
  }

  /// Forgets the runtime of the application.
  static void reset() {
    _current = null;
  }
}
