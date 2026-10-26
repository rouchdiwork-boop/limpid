// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Exposes the session of the current author.
///
/// The value is `null` when nobody is signed in. The stream never throws: an
/// authentication outage leaves the author signed out rather than breaking the
/// interface.

@ProviderFor(sessionController)
const sessionControllerProvider = SessionControllerProvider._();

/// Exposes the session of the current author.
///
/// The value is `null` when nobody is signed in. The stream never throws: an
/// authentication outage leaves the author signed out rather than breaking the
/// interface.

final class SessionControllerProvider
    extends
        $FunctionalProvider<
          AsyncValue<AuthSession?>,
          AuthSession?,
          Stream<AuthSession?>
        >
    with $FutureModifier<AuthSession?>, $StreamProvider<AuthSession?> {
  /// Exposes the session of the current author.
  ///
  /// The value is `null` when nobody is signed in. The stream never throws: an
  /// authentication outage leaves the author signed out rather than breaking the
  /// interface.
  const SessionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionControllerHash();

  @$internal
  @override
  $StreamProviderElement<AuthSession?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<AuthSession?> create(Ref ref) {
    return sessionController(ref);
  }
}

String _$sessionControllerHash() => r'a90f89c335dc726b14dedb54dfffeecd8364894d';
