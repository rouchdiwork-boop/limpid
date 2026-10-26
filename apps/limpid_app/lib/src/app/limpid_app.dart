import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/app/theme_controller.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The root widget of the Limpid application.
///
/// It owns the four themes of the design system. The variant is a global,
/// user owned choice (D-14): the application never follows the system
/// brightness on its own, it follows the author.
class LimpidApp extends ConsumerWidget {
  /// Creates the application.
  const LimpidApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final variant = ref.watch(themeControllerProvider);

    return MaterialApp.router(
      title: 'Limpid',
      debugShowCheckedModeBanner: false,
      theme: LimpidTheme.of(variant),
      themeMode: variant.isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 2,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
