import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:limpid_app/l10n/generated/app_localizations.dart';

/// The kind of authentication failure.
///
/// The kind drives the message shown to the author. The messages themselves
/// come from the localizations: the authentication layer never writes a user
/// facing string.
enum AuthErrorKind {
  /// The address is not a valid e-mail address.
  invalidEmail,

  /// The backend refused the credentials: unknown address or wrong password.
  ///
  /// The backend does not tell the two apart, on purpose: it must not reveal
  /// which addresses have an account.
  rejected,

  /// The backend could not be reached.
  unavailable,

  /// The author sent too many requests.
  tooManyAttempts,

  /// The backend did not answer in time.
  timeout,
}

/// The message shown to the author for [kind].
///
/// The strings come from the localizations of the application. Several kinds
/// share the generic message of the application: the localizations do not
/// have a dedicated key for them yet.
String authErrorMessage(AuthErrorKind kind, AppLocalizations strings) {
  return switch (kind) {
    AuthErrorKind.invalidEmail => strings.errorInvalidEmail,
    AuthErrorKind.rejected => strings.errorGeneric,
    AuthErrorKind.unavailable => strings.errorGeneric,
    AuthErrorKind.tooManyAttempts => strings.errorGeneric,
    AuthErrorKind.timeout => strings.errorGeneric,
  };
}

/// The localizations of the locale of the platform.
///
/// The authentication layer has no `BuildContext`: the strings are resolved
/// from the locale of the platform, the way the application resolves it.
AppLocalizations get currentLocalizations =>
    lookupAppLocalizations(_platformLocale());

/// The locale of the platform, restricted to the supported locales.
Locale _platformLocale() {
  final supported = AppLocalizations.supportedLocales;
  final locale = PlatformDispatcher.instance.locale;
  return supported.firstWhere(
    (candidate) => candidate.languageCode == locale.languageCode,
    orElse: () => supported.first,
  );
}
