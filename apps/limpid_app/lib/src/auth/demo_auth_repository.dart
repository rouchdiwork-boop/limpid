import 'dart:async';
import 'dart:math';

import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/local_auth_store.dart';
import 'package:limpid_app/src/auth/session_stream.dart';

/// The repository of the demonstration mode.
///
/// The session is opened locally: no data leaves the device. The session is
/// persisted, so that the author finds it again after a restart, and the
/// identifier of the local author never changes: the demonstration session
/// always belongs to the same author.
final class DemoAuthRepository implements AuthRepository {
  /// Creates the repository.
  ///
  /// [session] is the session restored before the first frame, when there is
  /// one. [store] keeps the session between two runs of the application.
  factory DemoAuthRepository({LocalAuthStore? store, AuthSession? session}) =>
      DemoAuthRepository._(store ?? InMemoryLocalAuthStore(), session);

  DemoAuthRepository._(this._store, this._session);

  final LocalAuthStore _store;
  final StreamController<AuthSession?> _updates =
      StreamController<AuthSession?>.broadcast();
  AuthSession? _session;

  @override
  Stream<AuthSession?> watchSession() =>
      SessionStream(current: () => _session, updates: _updates.stream);

  @override
  Future<void> sendMagicLink(String email, {String? authorName}) async {
    if (!isValidEmail(email)) throw const InvalidEmailException();
    await _openSession(email, authorName);
  }

  @override
  Future<void> signInWithPassword(String email, String password) async {
    if (!isValidEmail(email)) throw const InvalidEmailException();
    if (password.isEmpty) throw const AuthRejectedException();
    await _openSession(email, null);
  }

  @override
  Future<void> signOut() async {
    final state = await _store.read();
    await _store.write(
      LocalAuthState(
        authorId: state?.authorId ?? _newAuthorId(),
        session: null,
      ),
    );
    _session = null;
    _updates.add(null);
  }

  /// Opens the local session of [email] and persists it.
  Future<void> _openSession(String email, String? authorName) async {
    final state = await _store.read();
    final authorId = state?.authorId ?? _newAuthorId();
    final session = AuthSession(
      userId: authorId,
      email: email,
      authorName: authorName,
    );
    await _store.write(LocalAuthState(authorId: authorId, session: session));
    _session = session;
    _updates.add(session);
  }

  /// A new identifier for the local author.
  String _newAuthorId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
