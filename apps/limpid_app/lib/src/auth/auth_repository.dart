import 'package:flutter/foundation.dart';
import 'package:limpid_app/src/auth/auth_errors.dart';

/// The authenticated session of the current author.
@immutable
class AuthSession {
  /// Creates a session.
  const AuthSession({
    required this.userId,
    required this.email,
    this.authorName,
  });

  /// The identifier of the author in the backend.
  final String userId;

  /// The e-mail address of the author.
  final String email;

  /// The public name of the author, used on the public pages.
  final String? authorName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthSession &&
          other.userId == userId &&
          other.email == email &&
          other.authorName == authorName);

  @override
  int get hashCode => Object.hash(userId, email, authorName);
}

/// Gives access to the authentication of the author.
abstract interface class AuthRepository {
  /// Emits the current session, and every subsequent change.
  Stream<AuthSession?> watchSession();

  /// Sends a magic link to [email], creating the account when needed.
  ///
  /// When [authorName] is provided it is stored as the public name of the
  /// author.
  Future<void> sendMagicLink(String email, {String? authorName});

  /// Signs the author in with a password.
  Future<void> signInWithPassword(String email, String password);

  /// Signs the author out.
  Future<void> signOut();
}

/// A repository that exposes the bearer token of the session that is open.
///
/// The synchronisation transport sends the token with every request. The
/// demonstration mode has no remote service: it does not implement this
/// interface, and the transport then sends anonymous requests.
abstract interface class AccessTokenReader {
  /// The access token of the current session, `null` when there is none.
  Future<String?> readAccessToken();
}

/// Errors raised by an [AuthRepository].
///
/// The exceptions carry the [kind] of the failure, never a message: the
/// message shown to the author is resolved from the localizations by the
/// interface.
sealed class AuthException implements Exception {
  /// Creates the exception.
  const AuthException();

  /// The kind of the failure.
  AuthErrorKind get kind;

  /// The message shown to the author, in the locale of the platform.
  ///
  /// The interface usually resolves the message with [authErrorMessage] and
  /// the localizations of the application, so that the message follows the
  /// language chosen by the author.
  String get message => authErrorMessage(kind, currentLocalizations);

  @override
  String toString() => message;
}

/// The e-mail address is not a valid address.
final class InvalidEmailException extends AuthException {
  /// Creates the exception.
  const InvalidEmailException();

  @override
  AuthErrorKind get kind => AuthErrorKind.invalidEmail;
}

/// The credentials were refused by the backend.
final class AuthRejectedException extends AuthException {
  /// Creates the exception.
  const AuthRejectedException();

  @override
  AuthErrorKind get kind => AuthErrorKind.rejected;
}

/// The backend could not be reached.
final class AuthUnavailableException extends AuthException {
  /// Creates the exception.
  const AuthUnavailableException();

  @override
  AuthErrorKind get kind => AuthErrorKind.unavailable;
}

/// The author sent too many requests.
final class AuthTooManyAttemptsException extends AuthException {
  /// Creates the exception.
  const AuthTooManyAttemptsException();

  @override
  AuthErrorKind get kind => AuthErrorKind.tooManyAttempts;
}

/// The backend did not answer in time.
final class AuthTimeoutException extends AuthException {
  /// Creates the exception.
  const AuthTimeoutException();

  @override
  AuthErrorKind get kind => AuthErrorKind.timeout;
}

/// Whether [email] is a valid e-mail address.
bool isValidEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
