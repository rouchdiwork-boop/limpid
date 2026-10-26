import 'package:flutter/material.dart';
import 'package:limpid_app/src/domain/search_repository.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// A passage found by the search.
///
/// The tile shows the scene that carries the passage, the book it belongs to
/// and the passage itself. The words of the query are painted apart: the
/// writer sees where the passage was found without reading it twice.
class SearchResultTile extends StatelessWidget {
  /// Creates a tile.
  const SearchResultTile({required this.result, this.onTap, super.key});

  /// The passage the tile shows.
  final SearchResult result;

  /// Called when the author picks the passage.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Material(
      color: LimpidColors.transparent,
      borderRadius: BorderRadius.circular(scope.radii.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: scope.spacing.space16,
            vertical: scope.spacing.space12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    LimpidIcons.search,
                    size: 16,
                    color: scope.colors.fgSubtle,
                  ),
                  SizedBox(width: scope.spacing.space8),
                  Expanded(
                    child: Text(
                      _headline(),
                      style: textTheme.bodyLarge?.copyWith(
                        color: scope.colors.fgDefault,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (result.projectTitle.isNotEmpty) ...<Widget>[
                SizedBox(height: scope.spacing.space4),
                Text(
                  result.projectTitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: scope.colors.fgMuted,
                  ),
                ),
              ],
              SizedBox(height: scope.spacing.space8),
              _Excerpt(result: result),
            ],
          ),
        ),
      ),
    );
  }

  /// The title of the tile: the scene when the passage has one, the book
  /// otherwise.
  String _headline() {
    if (result.sceneTitle.isNotEmpty) return result.sceneTitle;
    return result.projectTitle;
  }
}

/// The passage of a result, with the words of the query painted apart.
class _Excerpt extends StatelessWidget {
  /// Creates the passage.
  const _Excerpt({required this.result});

  /// The result the passage belongs to.
  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final TextStyle base = textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final TextStyle marked = base.copyWith(
      color: scope.colors.fgDefault,
      fontWeight: FontWeight.w600,
      backgroundColor: scope.colors.accentSubtle,
    );

    return RichText(
      text: TextSpan(
        style: base.copyWith(color: scope.colors.fgMuted),
        children: _spans(result.excerpt, result.highlights, marked),
      ),
    );
  }

  /// Cuts the excerpt around the passages the query was found in.
  List<InlineSpan> _spans(
    String excerpt,
    List<SearchHighlight> highlights,
    TextStyle marked,
  ) {
    final List<InlineSpan> spans = <InlineSpan>[];
    int cursor = 0;
    for (final SearchHighlight highlight in highlights) {
      if (highlight.start < cursor || highlight.end > excerpt.length) continue;
      if (highlight.start > cursor) {
        spans.add(TextSpan(text: excerpt.substring(cursor, highlight.start)));
      }
      spans.add(
        TextSpan(
          text: excerpt.substring(highlight.start, highlight.end),
          style: marked,
        ),
      );
      cursor = highlight.end;
    }
    if (cursor < excerpt.length) {
      spans.add(TextSpan(text: excerpt.substring(cursor)));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: excerpt));
    }
    return spans;
  }
}
