import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_providers.dart';
import 'package:limpid_app/src/features/library/library_states.dart';
import 'package:limpid_app/src/features/library/library_tile.dart';
import 'package:limpid_app/src/features/projects/project_metrics.dart';
import 'package:limpid_app/src/features/projects/project_summary.dart';
import 'package:limpid_app/src/features/projects/projects_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The library of the author's projects.
///
/// The manuscripts come from the repository, the filter follows the editorial
/// stage of the manuscripts and the counters of the header are computed from
/// the manuscripts themselves.
class LibraryScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  ManuscriptStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final AsyncValue<LibrarySnapshot> library = ref.watch(libraryProvider);
    final String authorName = ref.watch(authorNameProvider);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.all(scope.spacing.space24),
        children: <Widget>[
          _LibraryHeader(
            snapshot: library.value,
            onNewProject: () => context.go(AppRoutes.onboarding),
          ),
          SizedBox(height: scope.spacing.space20),
          _FilterBar(filter: _filter, onChanged: _selectFilter),
          SizedBox(height: scope.spacing.space20),
          library.when(
            loading: () => const LibraryLoading(),
            error: (Object error, StackTrace stackTrace) =>
                LibraryFailure(onRetry: () => ref.invalidate(libraryProvider)),
            data: (LibrarySnapshot snapshot) => _LibraryContent(
              snapshot: snapshot,
              filter: _filter,
              authorName: authorName,
            ),
          ),
        ],
      ),
    );
  }

  /// Keeps the stage the author filters on.
  void _selectFilter(ManuscriptStatus? status) {
    setState(() => _filter = status);
  }
}

/// The header of the library.
class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.snapshot, required this.onNewProject});

  /// The library of the author, `null` while it is being read.
  final LibrarySnapshot? snapshot;

  /// Called when the author asks for a new project.
  final VoidCallback onNewProject;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final LibrarySnapshot? library = snapshot;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                strings.libraryTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: scope.colors.fgDefault,
                  fontWeight: FontWeight.w600,
                  fontFamily: LimpidFontFamily.display,
                ),
              ),
              SizedBox(height: scope.spacing.space4),
              if (library != null)
                Text(
                  strings.librarySubtitle(
                    library.projectCount,
                    library.countByStatus(ManuscriptStatus.published),
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
                ),
            ],
          ),
        ),
        SizedBox(width: scope.spacing.space16),
        LimpidButton(
          label: strings.actionNewProject,
          icon: LimpidIcons.add,
          size: LimpidButtonSize.small,
          onPressed: onNewProject,
        ),
      ],
    );
  }
}

/// The bar of the filters of the library.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.onChanged});

  /// The stage the library is filtered on, `null` when there is no filter.
  final ManuscriptStatus? filter;

  /// Called when the author chooses a stage.
  final ValueChanged<ManuscriptStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        LimpidChip(
          label: strings.libraryFilterAll,
          isSelected: filter == null,
          onTap: () => onChanged(null),
        ),
        LimpidChip(
          label: strings.libraryFilterWriting,
          isSelected: filter == ManuscriptStatus.writing,
          onTap: () => onChanged(ManuscriptStatus.writing),
        ),
        LimpidChip(
          label: strings.libraryFilterDraft,
          isSelected: filter == ManuscriptStatus.draft,
          onTap: () => onChanged(ManuscriptStatus.draft),
        ),
        LimpidChip(
          label: strings.libraryFilterPublished,
          isSelected: filter == ManuscriptStatus.published,
          onTap: () => onChanged(ManuscriptStatus.published),
        ),
      ],
    );
  }
}

/// The manuscripts of the library.
class _LibraryContent extends StatelessWidget {
  const _LibraryContent({
    required this.snapshot,
    required this.filter,
    required this.authorName,
  });

  /// The library of the author.
  final LibrarySnapshot snapshot;

  /// The stage the library is filtered on.
  final ManuscriptStatus? filter;

  /// The public name of the author.
  final String authorName;

  /// The width a tile of the library takes.
  static const double _tileWidth = 190;

  /// The smallest number of columns of the library.
  static const int _minColumns = 2;

  /// The largest number of columns of the library.
  static const int _maxColumns = 6;

  /// The ratio of the height of a tile against its width.
  static const double _tileRatio = 0.52;

  @override
  Widget build(BuildContext context) {
    final List<ProjectSummary> visible = filter == null
        ? snapshot.projects
        : snapshot.projects
              .where((ProjectSummary project) => project.status == filter)
              .toList(growable: false);

    if (visible.isEmpty) {
      return filter == null ? const LibraryEmpty() : const LibraryFilterEmpty();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final LimpidThemeScope scope = context.limpid;
        final int columns = (constraints.maxWidth / _tileWidth).floor().clamp(
          _minColumns,
          _maxColumns,
        );
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: scope.spacing.space24,
            crossAxisSpacing: scope.spacing.space20,
            childAspectRatio: _tileRatio,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) =>
              LibraryTile(project: visible[index], authorName: authorName),
        );
      },
    );
  }
}
