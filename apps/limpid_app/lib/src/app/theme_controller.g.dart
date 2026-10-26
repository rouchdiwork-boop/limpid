// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Stores the theme variant chosen by the author.
///
/// The variant is a global, single choice (D-14). It is applied instantly and
/// persisted by the implementation injected in [themePreferenceStoreProvider].

@ProviderFor(ThemeController)
const themeControllerProvider = ThemeControllerProvider._();

/// Stores the theme variant chosen by the author.
///
/// The variant is a global, single choice (D-14). It is applied instantly and
/// persisted by the implementation injected in [themePreferenceStoreProvider].
final class ThemeControllerProvider
    extends $NotifierProvider<ThemeController, LimpidThemeVariant> {
  /// Stores the theme variant chosen by the author.
  ///
  /// The variant is a global, single choice (D-14). It is applied instantly and
  /// persisted by the implementation injected in [themePreferenceStoreProvider].
  const ThemeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeControllerHash();

  @$internal
  @override
  ThemeController create() => ThemeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LimpidThemeVariant value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LimpidThemeVariant>(value),
    );
  }
}

String _$themeControllerHash() => r'bb255e220e0a7afbd61d317cf71479bbf42ae195';

/// Stores the theme variant chosen by the author.
///
/// The variant is a global, single choice (D-14). It is applied instantly and
/// persisted by the implementation injected in [themePreferenceStoreProvider].

abstract class _$ThemeController extends $Notifier<LimpidThemeVariant> {
  LimpidThemeVariant build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<LimpidThemeVariant, LimpidThemeVariant>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LimpidThemeVariant, LimpidThemeVariant>,
              LimpidThemeVariant,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Provides the [ThemePreferenceStore] used by the application.

@ProviderFor(themePreferenceStore)
const themePreferenceStoreProvider = ThemePreferenceStoreProvider._();

/// Provides the [ThemePreferenceStore] used by the application.

final class ThemePreferenceStoreProvider
    extends
        $FunctionalProvider<
          ThemePreferenceStore,
          ThemePreferenceStore,
          ThemePreferenceStore
        >
    with $Provider<ThemePreferenceStore> {
  /// Provides the [ThemePreferenceStore] used by the application.
  const ThemePreferenceStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themePreferenceStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themePreferenceStoreHash();

  @$internal
  @override
  $ProviderElement<ThemePreferenceStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ThemePreferenceStore create(Ref ref) {
    return themePreferenceStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemePreferenceStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemePreferenceStore>(value),
    );
  }
}

String _$themePreferenceStoreHash() =>
    r'3147335c95b7b0eedcdde15a3e02d3f0c3c2eed9';
