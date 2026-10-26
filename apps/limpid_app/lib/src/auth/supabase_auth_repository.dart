import 'dart:async';

import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/auth_runtime.dart';
import 'package:limpid_app/src/auth/demo_auth_repository.dart';
import 'package:limpid_app/src/auth/session_stream.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

export 'demo_auth_repository.dart';

part 'supabase_auth_repository.g.dart';

/// The time an authentication request may take.
///
/// The request is abandoned when the backend does not answer in time: the
/// author is not left waiting in front of a button that never reacts.
const Duration authRequestTimeout = Duration(seconds: 20);

/// [AuthRepository] backed by Supabase Auth.
///
/// The magic link is the primary path (D-15, the password is a fallback): the
/// author never has to invent or remember a password.
final class SupabaseAuthRepository
    implements AuthRepository, AccessTokenReader {
  /// Creates the repository on top of a Supabase client.
  const SupabaseAuthRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<String?> readAccessToken() async =>
      _client.auth.currentSession?.accessToken;

  @override
  Stream<AuthSession?> watchSession() => SessionStream(
    current: () => supabaseSession(_client.auth.currentSession),
    updates: _client.auth.onAuthStateChange.map(
      (state) => supabaseSession(state.session),
    ),
  );

  @override
  Future<void> sendMagicLink(String email, {String? authorName}) async {
    if (!isValidEmail(email)) throw const InvalidEmailException();
    try {
      await _client.auth
          .signInWithOtp(
            email: email,
            emailRedirectTo: _redirectUrl,
            data: authorName == null
                ? null
                : <String, String>{'author_name': authorName},
          )
          .timeout(authRequestTimeout);
    } on TimeoutException {
      throw const AuthTimeoutException();
    } on sb.AuthException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> signInWithPassword(String email, String password) async {
    if (!isValidEmail(email)) throw const InvalidEmailException();
    if (password.isEmpty) throw const AuthRejectedException();
    try {
      await _client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(authRequestTimeout);
    } on TimeoutException {
      throw const AuthTimeoutException();
    } on sb.AuthException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  /// Where Supabase must send the author back after clicking the magic link.
  String get _redirectUrl {
    final base = Uri.base;
    // The application does not always run on a web origin: the deep link of
    // the platform is used instead.
    final origin = base.isScheme('http') || base.isScheme('https')
        ? base.origin
        : base.toString();
    return '$origin/auth/callback';
  }

  /// The typed error that matches the failure of the backend.
  AuthException _translate(sb.AuthException error) {
    final message = error.message.toLowerCase();
    final status = error.statusCode;

    if (status == '429' ||
        message.contains('rate limit') ||
        message.contains('too many')) {
      return const AuthTooManyAttemptsException();
    }
    if (message.contains('invalid login credentials') ||
        message.contains('user not found') ||
        message.contains('email not confirmed') ||
        error.code == 'invalid_grant') {
      return const AuthRejectedException();
    }
    if (message.contains('invalid email') ||
        (message.contains('email') && message.contains('invalid'))) {
      return const InvalidEmailException();
    }
    return const AuthUnavailableException();
  }
}

/// The session of the author, `null` when nobody is signed in.
AuthSession? supabaseSession(sb.Session? session) {
  if (session == null) return null;
  final user = session.user;
  final authorName = user.userMetadata?['author_name'];
  return AuthSession(
    userId: user.id,
    email: user.email ?? '',
    authorName: authorName is String ? authorName : null,
  );
}

/// Provides the [AuthRepository] used by the application.
///
/// The runtime resolved by the bootstrap decides the mode: the demonstration
/// mode when no backend is configured, Supabase otherwise.
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  final runtime = AuthRuntimeHolder.current;
  return switch (runtime) {
    DemoAuthRuntime(:final store, :final session) => DemoAuthRepository(
      store: store,
      session: session,
    ),
    SupabaseAuthRuntime(:final client) => SupabaseAuthRepository(client),
  };
}
