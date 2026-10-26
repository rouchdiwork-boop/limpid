import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'theme_controller.g.dart';

/// Stores the theme variant chosen by the author.
///
/// The variant is a global, single choice (D-14). It is applied instantly and
/// persisted by the implementation injected in [themePreferenceStoreProvider].
@Riverpod(keepAlive: true)
class ThemeController extends _$ThemeController {
  @override
  LimpidThemeVariant build() {
    final store = ref.watch(themePreferenceStoreProvider);
    return store.read();
  }

  /// Applies a new theme variant and persists it.
  void select(LimpidThemeVariant variant) {
    if (variant == state) return;
    state = variant;
    ref.read(themePreferenceStoreProvider).write(variant);
  }
}

/// Persists the chosen theme variant between two launches.
abstract interface class ThemePreferenceStore {
  /// Reads the persisted variant, or the default one.
  LimpidThemeVariant read();

  /// Persists the variant.
  void write(LimpidThemeVariant variant);
}

/// In-memory implementation used until the local database lands.
final class MemoryThemePreferenceStore implements ThemePreferenceStore {
  /// Creates the store with an optional initial variant.
  MemoryThemePreferenceStore([this._variant = LimpidThemeVariant.paper]);

  LimpidThemeVariant _variant;

  @override
  LimpidThemeVariant read() => _variant;

  @override
  void write(LimpidThemeVariant variant) => _variant = variant;
}

/// Provides the [ThemePreferenceStore] used by the application.
@Riverpod(keepAlive: true)
ThemePreferenceStore themePreferenceStore(Ref ref) =>
    MemoryThemePreferenceStore();
