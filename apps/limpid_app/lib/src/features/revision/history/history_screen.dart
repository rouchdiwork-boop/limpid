import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/features/revision/history/history_providers.dart';
import 'package:limpid_app/src/features/revision/history/history_widgets.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The history of the versions of a document.
///
/// The screen shows the **revisions** of the manuscript — the points of the
/// history the CRDT holds — and the detail of the revision the author
/// picked: the blocks that changed, and how they changed.
///
/// The detail never says "three blocks changed": it shows the text a block
/// held before the change and the text it holds after, or the place it moved
/// from and the place it moved to.
class HistoryScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const HistoryScreen({required this.documentId, super.key});

  /// The document whose history the screen shows.
  final String documentId;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  VersionRef? _selected;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<DocumentRevision>> revisions = ref.watch(
      historyRevisionsProvider(widget.documentId),
    );

    return Scaffold(
      body: SafeArea(
        child: revisions.when(
          data: (List<DocumentRevision> list) => _body(context, list),
          loading: () =>
              const Center(child: LimpidSpinner(size: LimpidSpinnerSize.large)),
          error: (Object error, StackTrace stack) => LimpidEmptyState(
            title: AppLocalizations.of(context).historyFailureTitle,
            message: AppLocalizations.of(context).historyFailureMessage,
          ),
        ),
      ),
    );
  }

  /// The body of the screen: the revisions, and the detail of the selected
  /// one.
  Widget _body(BuildContext context, List<DocumentRevision> revisions) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    if (revisions.isEmpty) {
      return LimpidEmptyState(
        title: strings.historyEmptyTitle,
        message: strings.historyEmptyMessage,
      );
    }
    final int index = _indexOf(revisions);
    final HistorySelection? selection = _selectionOf(revisions, index);
    final VersionRef selected = revisions[index].ref;

    return ListView(
      padding: EdgeInsets.all(scope.spacing.space24),
      children: <Widget>[
        _HistoryHeader(strings: strings),
        SizedBox(height: scope.spacing.space16),
        // Les revisions les plus recentes d'abord : l'historique se lit
        // comme le journal d'un manuscrit, du dernier chapitre au premier.
        // Le detail de la revision choisie vient juste sous sa ligne : la
        // difference se lit sans defiler.
        for (final DocumentRevision revision in revisions.reversed) ...<Widget>[
          HistoryRevisionTile(
            revision: revision,
            isSelected: revision.ref == selected,
            onTap: () => setState(() => _selected = revision.ref),
          ),
          if (revision.ref == selected && selection != null) ...<Widget>[
            SizedBox(height: scope.spacing.space12),
            _HistoryDetail(selection: selection),
          ],
          SizedBox(height: scope.spacing.space4),
        ],
      ],
    );
  }

  /// The index of the selected revision, the newest one by default.
  int _indexOf(List<DocumentRevision> revisions) {
    final VersionRef? selected = _selected;
    if (selected == null) return revisions.length - 1;
    final int index = revisions.indexWhere(
      (DocumentRevision revision) => revision.ref == selected,
    );
    return index < 0 ? revisions.length - 1 : index;
  }

  /// The two revisions the detail compares.
  ///
  /// A revision is compared with the one that precedes it; the oldest
  /// revision is compared with the origin of the document.
  HistorySelection? _selectionOf(List<DocumentRevision> revisions, int index) {
    if (revisions.isEmpty) return null;
    final VersionRef to = revisions[index].ref;
    final VersionRef from = index == 0
        ? originRevision
        : revisions[index - 1].ref;
    return HistorySelection(documentId: widget.documentId, from: from, to: to);
  }
}

/// The header of the screen.
class _HistoryHeader extends StatelessWidget {
  /// Creates the header.
  const _HistoryHeader({required this.strings});

  /// The strings of the application.
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.historyTitle,
          style: textTheme.headlineMedium?.copyWith(
            color: scope.colors.fgDefault,
            fontWeight: FontWeight.w600,
            fontFamily: LimpidFontFamily.display,
          ),
        ),
        SizedBox(height: scope.spacing.space4),
        Text(
          strings.historySubtitle,
          style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
        ),
      ],
    );
  }
}

/// The detail of a revision: the blocks it changed.
class _HistoryDetail extends ConsumerWidget {
  /// Creates the detail.
  const _HistoryDetail({required this.selection});

  /// The two revisions the detail compares.
  final HistorySelection selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<RevisionComparison> comparison = ref.watch(
      historyComparisonProvider(selection),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.historyDetailTitle,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: scope.colors.fgDefault),
        ),
        SizedBox(height: scope.spacing.space8),
        comparison.when(
          data: (RevisionComparison value) => _changes(context, strings, value),
          loading: () =>
              const Center(child: LimpidSpinner(size: LimpidSpinnerSize.small)),
          error: (Object error, StackTrace stack) => LimpidEmptyState(
            title: strings.historyFailureTitle,
            message: strings.historyFailureMessage,
          ),
        ),
      ],
    );
  }

  /// The cards of the blocks that changed.
  Widget _changes(
    BuildContext context,
    AppLocalizations strings,
    RevisionComparison comparison,
  ) {
    final LimpidThemeScope scope = context.limpid;
    if (comparison.isEmpty) {
      return Text(
        strings.historyNoChanges,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          strings.historyChangeSummary(
            comparison.movedCount,
            comparison.addedCount,
            comparison.modifiedCount,
            comparison.removedCount,
          ),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space12),
        for (final BlockChange change in comparison.changes) ...<Widget>[
          HistoryChangeCard(change: change),
          SizedBox(height: scope.spacing.space8),
        ],
      ],
    );
  }
}
