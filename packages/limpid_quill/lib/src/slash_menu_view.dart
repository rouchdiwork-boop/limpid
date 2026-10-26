import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'accessibility.dart';
import 'slash_menu.dart';

/// The slash menu of the manuscript editor.
///
/// The menu is a list of commands: it announces itself as a list, every
/// entry is a list item, and the highlighted entry is exposed as the
/// selected one.
class LimpidSlashMenu extends StatelessWidget {
  /// Creates the slash menu.
  const LimpidSlashMenu({
    super.key,
    required this.controller,
    this.width = kSlashMenuWidth,
    this.focusNode,
  });

  /// The controller driving the menu.
  final LimpidSlashMenuController controller;

  /// The width of the menu, in logical pixels.
  final double width;

  /// The focus node receiving the keyboard events of the menu.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Focus(
      focusNode: focusNode,
      canRequestFocus: focusNode != null,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (controller.handleKeyEvent(event)) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        container: true,
        label: 'Commandes d’insertion',
        child: Container(
          width: width,
          constraints: const BoxConstraints(maxHeight: kSlashMenuMaxHeight),
          decoration: BoxDecoration(
            color: tokens.colors.bgRaised,
            borderRadius: BorderRadius.circular(tokens.radii.md),
            border: Border.all(color: tokens.colors.borderDefault),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              vertical: tokens.spacing.space4,
              horizontal: tokens.spacing.space4,
            ),
            // The list role sits inside the scroll view so that the list
            // items are its direct semantic children.
            child: Semantics(
              role: SemanticsRole.list,
              explicitChildNodes: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int index = 0; index < controller.items.length; index++)
                    _LimpidSlashMenuEntry(
                      item: controller.items[index],
                      isSelected: index == controller.selectedIndex,
                      onTap: () {
                        controller.selectIndex(index);
                        controller.onSelected?.call(controller.items[index]);
                      },
                      textTheme: textTheme,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LimpidSlashMenuEntry extends StatelessWidget {
  const _LimpidSlashMenuEntry({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.textTheme,
  });

  final LimpidSlashMenuItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    return Semantics(
      role: SemanticsRole.listItem,
      container: true,
      selected: isSelected,
      label: item.label,
      hint: item.description,
      button: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinimumTapTarget),
        child: Material(
          color: isSelected
              ? tokens.colors.accentSubtle
              : tokens.colors.bgRaised,
          borderRadius: BorderRadius.circular(tokens.radii.sm),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(tokens.radii.sm),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.space8,
                vertical: tokens.spacing.space8,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    item.icon,
                    size: 20,
                    color: item.kind == LimpidSlashMenuItemKind.ai
                        ? tokens.colors.secondary
                        : tokens.colors.fgMuted,
                  ),
                  SizedBox(width: tokens.spacing.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(item.label, style: textTheme.bodyMedium),
                        Text(
                          item.description,
                          style: textTheme.bodySmall?.copyWith(
                            color: tokens.colors.fgMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
