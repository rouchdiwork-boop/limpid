import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/theme_controller.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The destinations of the application shell.
enum ShellDestination {
  /// The dashboard.
  dashboard(LimpidIcons.home),

  /// The library of the author's projects.
  library(LimpidIcons.library),

  /// The writing surface.
  writing(LimpidIcons.pen),

  /// The account and the settings.
  account(LimpidIcons.user),

  /// The subscription, the quotas and the invoices.
  subscription(LimpidIcons.money);

  const ShellDestination(this.icon);

  /// The icon of the destination.
  final IconData icon;
}

/// The frame of the application.
///
/// On a wide screen the destinations live in a navigation rail; on a narrow
/// one they move to a bottom bar, within thumb reach (D-18, 44 px targets).
class AppShell extends ConsumerWidget {
  /// Creates the shell.
  const AppShell({required this.navigationShell, super.key});

  /// The shell of the router, holding the navigation stack of each branch.
  final StatefulNavigationShell navigationShell;

  static const double _railBreakpoint = 900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= _railBreakpoint;

    final destinations = <_Destination>[
      _Destination(ShellDestination.dashboard, strings.navDashboard),
      _Destination(ShellDestination.library, strings.navLibrary),
      _Destination(ShellDestination.writing, strings.navWrite),
      _Destination(ShellDestination.account, strings.navAccount),
      _Destination(ShellDestination.subscription, strings.settingsPlan),
    ];

    final content = navigationShell;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            _LimpidRail(
              destinations: destinations,
              selectedIndex: navigationShell.currentIndex,
              onSelect: (index) => navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      body: content,
      bottomNavigationBar: _LimpidBottomBar(
        destinations: destinations,
        selectedIndex: navigationShell.currentIndex,
        onSelect: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.destination, this.label);

  final ShellDestination destination;
  final String label;
}

class _LimpidRail extends ConsumerWidget {
  const _LimpidRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = context.limpid;
    final variant = ref.watch(themeControllerProvider);

    return Container(
      width: 232,
      color: scope.colors.bgSurface,
      padding: EdgeInsets.symmetric(
        horizontal: scope.spacing.space12,
        vertical: scope.spacing.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(
              left: scope.spacing.space8,
              bottom: scope.spacing.space24,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  'Limpid',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scope.colors.fgDefault,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '.',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scope.colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < destinations.length; index++)
            Padding(
              padding: EdgeInsets.only(bottom: scope.spacing.space4),
              child: _RailItem(
                destination: destinations[index],
                selected: index == selectedIndex,
                onTap: () => onSelect(index),
              ),
            ),
          const Spacer(),
          _ThemeVariantSelector(variant: variant),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = context.limpid;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(scope.radii.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(horizontal: scope.spacing.space12),
          decoration: BoxDecoration(
            color: selected ? scope.colors.accentSubtle : null,
            borderRadius: BorderRadius.circular(scope.radii.md),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                destination.destination.icon,
                size: 18,
                color: selected ? scope.colors.accent : scope.colors.fgMuted,
              ),
              SizedBox(width: scope.spacing.space12),
              Expanded(
                child: Text(
                  destination.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selected
                        ? scope.colors.accent
                        : scope.colors.fgMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LimpidBottomBar extends StatelessWidget {
  const _LimpidBottomBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scope = context.limpid;

    return Container(
      decoration: BoxDecoration(
        color: scope.colors.bgSurface,
        border: Border(top: BorderSide(color: scope.colors.borderSubtle)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: 68,
        child: Row(
          children: <Widget>[
            for (var index = 0; index < destinations.length; index++)
              Expanded(
                child: Semantics(
                  selected: index == selectedIndex,
                  button: true,
                  label: destinations[index].label,
                  child: InkWell(
                    onTap: () => onSelect(index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          destinations[index].destination.icon,
                          size: 22,
                          color: index == selectedIndex
                              ? scope.colors.accent
                              : scope.colors.fgSubtle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          destinations[index].label,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: index == selectedIndex
                                    ? scope.colors.accent
                                    : scope.colors.fgSubtle,
                                fontWeight: index == selectedIndex
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeVariantSelector extends ConsumerWidget {
  const _ThemeVariantSelector({required this.variant});

  final LimpidThemeVariant variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = context.limpid;
    final strings = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          strings.settingsTheme,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scope.colors.fgSubtle,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in <LimpidThemeVariant, String>{
          LimpidThemeVariant.paper: strings.settingsThemePaper,
          LimpidThemeVariant.sepia: strings.settingsThemeSepia,
          LimpidThemeVariant.night: strings.settingsThemeNight,
          LimpidThemeVariant.contrast: strings.settingsThemeContrast,
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _ThemeSwatch(
              label: entry.value,
              variant: entry.key,
              selected: entry.key == variant,
              onTap: () =>
                  ref.read(themeControllerProvider.notifier).select(entry.key),
            ),
          ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.label,
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final LimpidThemeVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = context.limpid;
    final swatch = variant.colors;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(scope.radii.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(horizontal: scope.spacing.space8),
          decoration: BoxDecoration(
            color: selected ? scope.colors.accentSubtle : null,
            borderRadius: BorderRadius.circular(scope.radii.sm),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: swatch.bgCanvas,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: selected
                        ? scope.colors.accent
                        : scope.colors.borderDefault,
                    width: selected ? 2 : 1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? scope.colors.accent : scope.colors.fgMuted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
