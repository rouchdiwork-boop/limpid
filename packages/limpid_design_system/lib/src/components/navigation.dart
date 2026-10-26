import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/icons/limpid_icons.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';
import 'package:limpid_design_system/src/tokens/colors.dart';

/// A tab of a [LimpidTabs].
@immutable
class LimpidTab {
  /// Creates a tab.
  const LimpidTab({required this.label, this.icon});

  /// The label of the tab.
  final String label;

  /// An optional leading icon.
  final IconData? icon;
}

/// The tab bar of the Limpid design system.
///
/// The widget only owns the appearance: the caller owns the
/// [TabController] and the [TabBarView] it drives.
class LimpidTabs extends StatelessWidget {
  /// Creates a tab bar.
  const LimpidTabs({
    super.key,
    required this.tabs,
    required this.controller,
    this.isScrollable = false,
  });

  /// The tabs of the bar.
  final List<LimpidTab> tabs;

  /// The controller shared with the tab view.
  final TabController controller;

  /// Whether the bar scrolls horizontally.
  final bool isScrollable;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.colors.borderSubtle)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: isScrollable,
        tabs: tabs
            .map(
              (LimpidTab tab) => Tab(
                text: tab.label,
                icon: tab.icon == null ? null : Icon(tab.icon),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

/// An entry of a [LimpidBreadcrumb].
@immutable
class LimpidBreadcrumbItem {
  /// Creates a breadcrumb entry.
  const LimpidBreadcrumbItem({required this.label, this.onTap});

  /// The label of the entry.
  final String label;

  /// Called when the entry is clicked. A null callback makes it read only.
  final VoidCallback? onTap;

  /// Whether the entry can be navigated to.
  bool get isNavigable => onTap != null;
}

/// The breadcrumb of the Limpid design system.
///
/// The last entry is the current page: it is never a link.
class LimpidBreadcrumb extends StatelessWidget {
  /// Creates a breadcrumb.
  const LimpidBreadcrumb({
    super.key,
    required this.items,
    this.separatorIcon = LimpidIcons.chevronRight,
  });

  /// The entries of the breadcrumb.
  final List<LimpidBreadcrumbItem> items;

  /// The icon displayed between two entries.
  final IconData separatorIcon;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int index = 0; index < items.length; index++) ...<Widget>[
              if (index > 0) ...<Widget>[
                Icon(separatorIcon, size: 16, color: tokens.colors.fgSubtle),
                SizedBox(width: tokens.spacing.space4),
              ],
              _LimpidBreadcrumbEntry(
                item: items[index],
                isLast: index == items.length - 1,
                textStyle: textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LimpidBreadcrumbEntry extends StatelessWidget {
  const _LimpidBreadcrumbEntry({
    required this.item,
    required this.isLast,
    required this.textStyle,
  });

  final LimpidBreadcrumbItem item;
  final bool isLast;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final Color color = isLast ? tokens.colors.fgDefault : tokens.colors.accent;

    final Widget label = Text(
      item.label,
      style: textStyle?.copyWith(
        color: color,
        fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
      ),
    );

    if (!item.isNavigable) {
      return Semantics(label: item.label, child: label);
    }

    return Semantics(
      button: true,
      label: item.label,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(tokens.radii.xs),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.space4,
            vertical: tokens.spacing.space2,
          ),
          child: label,
        ),
      ),
    );
  }
}

/// The pagination of the Limpid design system.
class LimpidPagination extends StatelessWidget {
  /// Creates a pagination.
  const LimpidPagination({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPageChanged,
    this.siblingCount = 1,
    this.previousTooltip = 'Page précédente',
    this.nextTooltip = 'Page suivante',
  });

  /// The current page, starting at 1.
  final int page;

  /// The total number of pages.
  final int pageCount;

  /// Called with the new page number.
  final ValueChanged<int> onPageChanged;

  /// The number of pages displayed around the current one.
  final int siblingCount;

  /// The tooltip of the previous button.
  final String previousTooltip;

  /// The tooltip of the next button.
  final String nextTooltip;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    if (pageCount <= 1) {
      return const SizedBox.shrink();
    }

    return Semantics(
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            button: true,
            enabled: page > 1,
            label: previousTooltip,
            child: IconButton(
              onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
              tooltip: null,
              icon: const Icon(LimpidIcons.arrowLeft),
            ),
          ),
          for (final int number in _visiblePages()) ...<Widget>[
            _LimpidPageButton(
              page: number,
              isCurrent: number == page,
              onPressed: () => onPageChanged(number),
              textStyle: textTheme.labelMedium,
            ),
          ],
          Semantics(
            button: true,
            enabled: page < pageCount,
            label: nextTooltip,
            child: IconButton(
              onPressed: page < pageCount
                  ? () => onPageChanged(page + 1)
                  : null,
              tooltip: null,
              icon: const Icon(LimpidIcons.arrowRight),
            ),
          ),
        ],
      ),
    );
  }

  List<int> _visiblePages() {
    final int first = (page - siblingCount).clamp(1, pageCount);
    final int last = (page + siblingCount).clamp(1, pageCount);
    return <int>[for (int number = first; number <= last; number++) number];
  }
}

class _LimpidPageButton extends StatelessWidget {
  const _LimpidPageButton({
    required this.page,
    required this.isCurrent,
    required this.onPressed,
    required this.textStyle,
  });

  final int page;
  final bool isCurrent;
  final VoidCallback onPressed;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;

    return Semantics(
      button: true,
      selected: isCurrent,
      label: 'Page $page',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.space2),
        child: Material(
          color: isCurrent
              ? tokens.colors.accentSubtle
              : LimpidColors.transparent,
          borderRadius: BorderRadius.circular(tokens.radii.sm),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(tokens.radii.sm),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              alignment: Alignment.center,
              child: Text(
                '$page',
                style: textStyle?.copyWith(
                  color: isCurrent
                      ? tokens.colors.accent
                      : tokens.colors.fgMuted,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
