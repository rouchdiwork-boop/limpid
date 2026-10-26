import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/components/selection.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';

/// The searchable select of the Limpid design system.
///
/// The suggestions are displayed in an overlay anchored to the field, so the
/// layout of the surrounding screen never shifts while the user types.
class LimpidCombobox<T> extends StatefulWidget {
  /// Creates a combobox.
  const LimpidCombobox({
    super.key,
    required this.items,
    this.onSelected,
    this.label,
    this.hint,
    this.emptyMessage,
    this.enabled = true,
    this.semanticLabel,
  });

  /// The available items.
  final List<LimpidSelectItem<T>> items;

  /// Called when an item is picked.
  final ValueChanged<T>? onSelected;

  /// The floating label of the field.
  final String? label;

  /// The placeholder text.
  final String? hint;

  /// The message displayed when no item matches the query.
  final String? emptyMessage;

  /// Whether the combobox accepts input.
  final bool enabled;

  /// The label announced by screen readers.
  final String? semanticLabel;

  @override
  State<LimpidCombobox<T>> createState() => _LimpidComboboxState<T>();
}

class _LimpidComboboxState<T> extends State<LimpidCombobox<T>> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  final OverlayPortalController _overlayController = OverlayPortalController();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<LimpidSelectItem<T>> _matches = <LimpidSelectItem<T>>[];
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleQueryChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleQueryChanged)
      ..dispose();
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    final String query = _controller.text.trim().toLowerCase();
    final List<LimpidSelectItem<T>> matches = widget.items
        .where(
          (LimpidSelectItem<T> item) =>
              item.label.toLowerCase().contains(query),
        )
        .toList(growable: false);
    setState(() => _matches = matches);
    _open();
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _open();
    } else {
      _close();
    }
  }

  void _open() {
    if (!_isOpen && widget.enabled) {
      setState(() => _isOpen = true);
      _overlayController.show();
    }
  }

  void _close() {
    if (_isOpen) {
      setState(() => _isOpen = false);
      _overlayController.hide();
    }
  }

  void _select(LimpidSelectItem<T> item) {
    _controller.text = item.label;
    _controller.selection = TextSelection.collapsed(offset: item.label.length);
    widget.onSelected?.call(item.value);
    _close();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (BuildContext context) {
        final double width = _fieldWidth();
        return Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: _ComboboxPanel<T>(
                matches: _matches,
                emptyMessage: widget.emptyMessage,
                onSelected: _select,
                radius: tokens.radii.md,
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Semantics(
          textField: true,
          label: widget.semanticLabel ?? widget.label,
          child: TextField(
            key: _fieldKey,
            controller: _controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            onSubmitted: (_) => _close(),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              suffixIcon: _isOpen
                  ? const Icon(Icons.expand_less)
                  : const Icon(Icons.expand_more),
            ),
          ),
        ),
      ),
    );
  }

  double _fieldWidth() {
    final RenderObject? renderObject = _fieldKey.currentContext
        ?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size.width;
    }
    final Size screen = MediaQuery.sizeOf(context);
    return screen.width * 0.8;
  }
}

class _ComboboxPanel<T> extends StatelessWidget {
  const _ComboboxPanel({
    required this.matches,
    required this.onSelected,
    required this.radius,
    this.emptyMessage,
  });

  final List<LimpidSelectItem<T>> matches;
  final ValueChanged<LimpidSelectItem<T>> onSelected;
  final double radius;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Material(
      elevation: 3,
      color: tokens.colors.bgRaised,
      borderRadius: BorderRadius.circular(radius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: matches.isEmpty
            ? Padding(
                padding: EdgeInsets.all(tokens.spacing.space16),
                child: Text(
                  emptyMessage ?? '',
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.colors.fgMuted,
                  ),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: matches.length,
                itemBuilder: (BuildContext context, int index) {
                  final LimpidSelectItem<T> item = matches[index];
                  return Semantics(
                    button: true,
                    label: item.label,
                    child: InkWell(
                      onTap: () => onSelected(item),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: tokens.spacing.space16,
                          vertical: tokens.spacing.space12,
                        ),
                        child: Row(
                          children: <Widget>[
                            if (item.icon != null) ...<Widget>[
                              Icon(item.icon, size: 18),
                              SizedBox(width: tokens.spacing.space8),
                            ],
                            Expanded(child: Text(item.label)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
