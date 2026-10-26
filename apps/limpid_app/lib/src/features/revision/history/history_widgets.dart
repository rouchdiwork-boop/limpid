import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// A revision of the document, as the list of the history shows it.
class HistoryRevisionTile extends StatelessWidget {
  /// Creates a tile.
  const HistoryRevisionTile({
    required this.revision,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  /// The revision the tile shows.
  final DocumentRevision revision;

  /// Whether the revision is the one the detail shows.
  final bool isSelected;

  /// Called when the author picks the revision.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return LimpidListTile(
      title: strings.historyRevisionLabel(revision.lamport),
      subtitle: strings.historyBlockCount(revision.blockCount),
      leading: Icon(LimpidIcons.timeline, color: scope.colors.fgMuted),
      trailing: Text(
        revision.author.value,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scope.colors.fgSubtle),
      ),
      selected: isSelected,
      onTap: onTap,
    );
  }
}

/// The change of a block, as the detail of a revision shows it.
///
/// The card shows **the difference**: the text a block held before the
/// change and the text it holds after, or the place it moved from and the
/// place it moved to.
class HistoryChangeCard extends StatelessWidget {
  /// Creates a card.
  const HistoryChangeCard({required this.change, super.key});

  /// The change the card shows.
  final BlockChange change;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return LimpidCard(
      leading: Icon(_iconOf(change.kind), color: scope.colors.fgMuted),
      title: _labelOf(strings, change.kind),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(height: scope.spacing.space8),
          ..._detailsOf(context, strings),
        ],
      ),
    );
  }

  /// The detail of the change: the texts, or the places.
  List<Widget> _detailsOf(BuildContext context, AppLocalizations strings) {
    return switch (change.kind) {
      BlockChangeKind.added => <Widget>[_text(change.afterText)],
      BlockChangeKind.removed => <Widget>[_text(change.beforeText)],
      BlockChangeKind.modified => <Widget>[
        _labelledText(
          context,
          label: strings.historyChangeBefore,
          text: change.beforeText,
        ),
        _labelledText(
          context,
          label: strings.historyChangeAfter,
          text: change.afterText,
        ),
      ],
      BlockChangeKind.moved => <Widget>[
        _labelledPlace(
          context,
          label: strings.historyChangePlaceBefore(
            _placeOf(change.beforePosition, change.before),
          ),
        ),
        _labelledPlace(
          context,
          label: strings.historyChangePlaceAfter(
            _placeOf(change.afterPosition, change.after),
          ),
        ),
      ],
    };
  }

  /// The place a block held: its rank in the tree, or its order key when
  /// the rank is unknown.
  static String _placeOf(int? position, Block? block) {
    if (position != null) return position.toString();
    return block?.order.value ?? '';
  }

  /// A paragraph of text, in the card.
  Widget _text(String text) {
    return Text(
      text.isEmpty ? '—' : text,
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// A text with the label that tells whether it is the before or the after.
  Widget _labelledText(
    BuildContext context, {
    required String label,
    required String text,
  }) {
    final LimpidThemeScope scope = context.limpid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scope.colors.fgSubtle),
        ),
        SizedBox(height: scope.spacing.space4),
        _text(text),
        SizedBox(height: scope.spacing.space8),
      ],
    );
  }

  /// A place with the label that tells whether it is the old or the new one.
  Widget _labelledPlace(BuildContext context, {required String label}) {
    final LimpidThemeScope scope = context.limpid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space8),
      ],
    );
  }

  /// The label of a kind of change.
  static String _labelOf(AppLocalizations strings, BlockChangeKind kind) =>
      switch (kind) {
        BlockChangeKind.added => strings.historyChangeAdded,
        BlockChangeKind.removed => strings.historyChangeRemoved,
        BlockChangeKind.modified => strings.historyChangeModified,
        BlockChangeKind.moved => strings.historyChangeMoved,
      };

  /// The icon of a kind of change.
  static IconData _iconOf(BlockChangeKind kind) => switch (kind) {
    BlockChangeKind.added => LimpidIcons.add,
    BlockChangeKind.removed => LimpidIcons.delete,
    BlockChangeKind.modified => LimpidIcons.edit,
    BlockChangeKind.moved => LimpidIcons.dragHandle,
  };
}
