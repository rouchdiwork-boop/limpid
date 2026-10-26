import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/icons/limpid_icons.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';
import 'package:limpid_design_system/src/tokens/typography.dart';

/// A command of the [LimpidCommandPalette].
@immutable
class LimpidCommand {
  /// Creates a command.
  const LimpidCommand({
    required this.label,
    required this.value,
    this.icon,
    this.category,
    this.shortcut,
  });

  /// The label of the command.
  final String label;

  /// The value returned when the command is run.
  final Object value;

  /// An optional leading icon.
  final IconData? icon;

  /// An optional category, displayed on the right of the label.
  final String? category;

  /// An optional keyboard shortcut, displayed on the right.
  final String? shortcut;

  /// Whether the command matches a search query.
  bool matches(String query) {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return true;
    }
    return label.toLowerCase().contains(needle) ||
        (category?.toLowerCase().contains(needle) ?? false);
  }
}

/// The command palette of the Limpid design system.
///
/// It lets the user trigger any action of the application from a single
/// searchable list.
class LimpidCommandPalette extends StatelessWidget {
  /// Creates a command palette.
  const LimpidCommandPalette({
    super.key,
    required this.commands,
    required this.onSelected,
    this.hint,
    this.emptyMessage,
  });

  /// The available commands.
  final List<LimpidCommand> commands;

  /// Called when a command is run.
  final ValueChanged<LimpidCommand> onSelected;

  /// The placeholder of the search field.
  final String? hint;

  /// The message displayed when no command matches.
  final String? emptyMessage;

  /// Displays the command palette as a modal dialog.
  static Future<void> show({
    required BuildContext context,
    required List<LimpidCommand> commands,
    required ValueChanged<LimpidCommand> onSelected,
    String? hint,
    String? emptyMessage,
  }) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => LimpidCommandPalette(
        commands: commands,
        onSelected: onSelected,
        hint: hint,
        emptyMessage: emptyMessage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;

    return Dialog(
      backgroundColor: tokens.colors.bgRaised,
      surfaceTintColor: tokens.colors.bgRaised,
      insetPadding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.space24,
        vertical: tokens.spacing.space64,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radii.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
        child: _LimpidCommandPaletteBody(
          commands: commands,
          onSelected: onSelected,
          hint: hint,
          emptyMessage: emptyMessage,
        ),
      ),
    );
  }
}

/// The overlay that hosts a [LimpidCommandPalette].
///
/// It is useful when the palette must be displayed above a full screen
/// editor: the overlay keeps the palette reachable without pushing a route.
class LimpidCommandPaletteOverlay extends StatelessWidget {
  /// Creates an overlay hosting a command palette.
  const LimpidCommandPaletteOverlay({
    super.key,
    required this.commands,
    required this.onSelected,
    this.hint,
    this.emptyMessage,
  });

  /// The available commands.
  final List<LimpidCommand> commands;

  /// Called when a command is run.
  final ValueChanged<LimpidCommand> onSelected;

  /// The placeholder of the search field.
  final String? hint;

  /// The message displayed when no command matches.
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;

    return ColoredBox(
      color: tokens.colors.shadowTone.withValues(alpha: 0.4),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.space24),
          child: Material(
            color: tokens.colors.bgRaised,
            borderRadius: BorderRadius.circular(tokens.radii.lg),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 560,
              child: _LimpidCommandPaletteBody(
                commands: commands,
                onSelected: onSelected,
                hint: hint,
                emptyMessage: emptyMessage,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LimpidCommandPaletteBody extends StatefulWidget {
  const _LimpidCommandPaletteBody({
    required this.commands,
    required this.onSelected,
    this.hint,
    this.emptyMessage,
  });

  final List<LimpidCommand> commands;
  final ValueChanged<LimpidCommand> onSelected;
  final String? hint;
  final String? emptyMessage;

  @override
  State<_LimpidCommandPaletteBody> createState() =>
      _LimpidCommandPaletteBodyState();
}

class _LimpidCommandPaletteBodyState extends State<_LimpidCommandPaletteBody> {
  final TextEditingController _controller = TextEditingController();
  List<LimpidCommand> _matches = const <LimpidCommand>[];

  @override
  void initState() {
    super.initState();
    _matches = widget.commands;
    _controller.addListener(_handleQueryChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    final String query = _controller.text;
    setState(() {
      _matches = widget.commands
          .where((LimpidCommand command) => command.matches(query))
          .toList(growable: false);
    });
  }

  void _run(LimpidCommand command) {
    widget.onSelected(command);
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.all(tokens.spacing.space16),
          child: Semantics(
            textField: true,
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                if (_matches.isNotEmpty) {
                  _run(_matches.first);
                }
              },
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(LimpidIcons.search),
              ),
            ),
          ),
        ),
        Divider(color: tokens.colors.borderSubtle, height: 1),
        Flexible(
          child: _matches.isEmpty
              ? Padding(
                  padding: EdgeInsets.all(tokens.spacing.space24),
                  child: Text(
                    widget.emptyMessage ?? '',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.colors.fgMuted,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _matches.length,
                  itemBuilder: (BuildContext context, int index) {
                    final LimpidCommand command = _matches[index];
                    return Semantics(
                      button: true,
                      label: command.label,
                      child: InkWell(
                        onTap: () => _run(command),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.spacing.space16,
                            vertical: tokens.spacing.space12,
                          ),
                          child: Row(
                            children: <Widget>[
                              if (command.icon != null) ...<Widget>[
                                Icon(
                                  command.icon,
                                  size: 18,
                                  color: tokens.colors.fgMuted,
                                ),
                                SizedBox(width: tokens.spacing.space12),
                              ],
                              Expanded(
                                child: Text(
                                  command.label,
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                              if (command.category != null) ...<Widget>[
                                SizedBox(width: tokens.spacing.space8),
                                Text(
                                  command.category!,
                                  style: LimpidTypography.captionStyle(
                                    color: tokens.colors.fgSubtle,
                                  ),
                                ),
                              ],
                              if (command.shortcut != null) ...<Widget>[
                                SizedBox(width: tokens.spacing.space12),
                                Text(
                                  command.shortcut!,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: tokens.colors.fgSubtle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
