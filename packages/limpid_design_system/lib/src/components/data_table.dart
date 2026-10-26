import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/icons/limpid_icons.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';

/// A column of a [LimpidDataTable].
@immutable
class LimpidDataColumn {
  /// Creates a column.
  const LimpidDataColumn({
    required this.title,
    this.flex = 1,
    this.isNumeric = false,
    this.isSortable = true,
  });

  /// The header of the column.
  final String title;

  /// The relative width of the column.
  final double flex;

  /// Whether the content of the column is a number.
  final bool isNumeric;

  /// Whether the column can be sorted.
  final bool isSortable;
}

/// A row of a [LimpidDataTable].
@immutable
class LimpidDataRow {
  /// Creates a row.
  const LimpidDataRow({required this.cells, this.key, this.isSelected = false});

  /// The cells of the row, one per column.
  final List<Widget> cells;

  /// The stable identifier of the row, used by the selection.
  final String? key;

  /// Whether the row is selected.
  final bool isSelected;
}

/// The data table of the Limpid design system.
///
/// The table supports a sortable header and a selection column. It is a
/// controlled component: the caller owns the selection and the sort state.
class LimpidDataTable extends StatelessWidget {
  /// Creates a data table.
  const LimpidDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.selectedRowKeys = const <String>{},
    this.onSelectionChanged,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSortChanged,
    this.emptyState,
    this.onRowTap,
  });

  /// The columns of the table.
  final List<LimpidDataColumn> columns;

  /// The rows of the table.
  final List<LimpidDataRow> rows;

  /// The keys of the selected rows.
  final Set<String> selectedRowKeys;

  /// Called when the selection changes. A null callback hides the
  /// selection column.
  final ValueChanged<Set<String>>? onSelectionChanged;

  /// The index of the sorted column.
  final int? sortColumnIndex;

  /// Whether the sorted column is sorted in ascending order.
  final bool sortAscending;

  /// Called when the user sorts a column.
  final void Function(int columnIndex, bool isAscending)? onSortChanged;

  /// The widget displayed when the table has no row.
  final Widget? emptyState;

  /// Called when a row is tapped.
  final ValueChanged<LimpidDataRow>? onRowTap;

  bool get _hasSelection => onSelectionChanged != null;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    if (rows.isEmpty && emptyState != null) {
      return emptyState!;
    }

    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildHeader(context, textTheme, tokens),
          Divider(color: tokens.colors.borderDefault, height: 1),
          for (final LimpidDataRow row in rows)
            _buildRow(context, textTheme, tokens, row),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    TextTheme textTheme,
    LimpidThemeScope tokens,
  ) {
    return Container(
      color: tokens.colors.bgSunken,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.space16,
        vertical: tokens.spacing.space8,
      ),
      child: Row(
        children: <Widget>[
          if (_hasSelection) const _SelectionSlot(width: 44),
          for (int index = 0; index < columns.length; index++)
            Expanded(
              flex: columns[index].flex.round(),
              child: _HeaderCell(
                column: columns[index],
                isSorted: sortColumnIndex == index,
                isAscending: sortAscending,
                textStyle: textTheme.labelMedium,
                onTap: columns[index].isSortable && onSortChanged != null
                    ? () => onSortChanged!(index, sortColumnIndex != index)
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    TextTheme textTheme,
    LimpidThemeScope tokens,
    LimpidDataRow row,
  ) {
    final bool isSelected = _hasSelection
        ? row.key != null && selectedRowKeys.contains(row.key)
        : row.isSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          onTap: onRowTap == null ? null : () => onRowTap!(row),
          child: Container(
            color: isSelected ? tokens.colors.accentSubtle : null,
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spacing.space16,
              vertical: tokens.spacing.space12,
            ),
            child: Row(
              children: <Widget>[
                if (_hasSelection)
                  _SelectionSlot(
                    width: 44,
                    child: Semantics(
                      label: row.key,
                      selected: isSelected,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: row.key == null
                            ? null
                            : (bool? value) =>
                                  _toggleRow(row.key!, value ?? false),
                      ),
                    ),
                  ),
                for (int index = 0; index < columns.length; index++)
                  Expanded(
                    flex: columns[index].flex.round(),
                    child: Align(
                      alignment: columns[index].isNumeric
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: index < row.cells.length
                          ? row.cells[index]
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Divider(color: tokens.colors.borderSubtle, height: 1),
      ],
    );
  }

  void _toggleRow(String key, bool isSelected) {
    final Set<String> next = Set<String>.of(selectedRowKeys);
    if (isSelected) {
      next.add(key);
    } else {
      next.remove(key);
    }
    onSelectionChanged?.call(next);
  }
}

class _SelectionSlot extends StatelessWidget {
  const _SelectionSlot({required this.width, this.child});

  final double width;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: child ?? const SizedBox.shrink());
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.isSorted,
    required this.isAscending,
    required this.textStyle,
    this.onTap,
  });

  final LimpidDataColumn column;
  final bool isSorted;
  final bool isAscending;
  final TextStyle? textStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;

    final Widget content = Row(
      mainAxisAlignment: column.isNumeric
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: <Widget>[
        Flexible(
          child: Text(
            column.title,
            overflow: TextOverflow.ellipsis,
            style: textStyle?.copyWith(
              color: isSorted ? tokens.colors.accent : tokens.colors.fgMuted,
            ),
          ),
        ),
        if (isSorted) ...<Widget>[
          SizedBox(width: tokens.spacing.space4),
          Icon(
            isAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: tokens.colors.accent,
          ),
        ],
      ],
    );

    if (onTap == null) {
      return content;
    }

    return Semantics(
      button: true,
      label: column.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radii.xs),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: column.isNumeric
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: content,
        ),
      ),
    );
  }
}

/// The empty table placeholder of the Limpid design system.
class LimpidDataTableEmpty extends StatelessWidget {
  /// Creates an empty table placeholder.
  const LimpidDataTableEmpty({
    super.key,
    required this.message,
    this.icon = LimpidIcons.empty,
  });

  /// The message displayed in the placeholder.
  final String message;

  /// The icon displayed above the message.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.all(tokens.spacing.space32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 32, color: tokens.colors.fgSubtle),
          SizedBox(height: tokens.spacing.space12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: tokens.colors.fgMuted),
          ),
        ],
      ),
    );
  }
}
