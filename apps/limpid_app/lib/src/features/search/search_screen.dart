import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/search_repository.dart';
import 'package:limpid_app/src/features/search/search_navigation.dart';
import 'package:limpid_app/src/features/search/search_providers.dart';
import 'package:limpid_app/src/features/search/search_result_tile.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The time the screen waits before it searches.
///
/// The search is local and fast: the wait is only there to avoid running a
/// search for every letter the author types.
const Duration _searchDelay = Duration(milliseconds: 200);

/// The search of the manuscript of the author.
///
/// The screen is **local**: every passage it shows comes from the index of
/// the device, and nothing is asked to the network. The author finds a
/// passage in his book even without a connection.
///
/// Picking a passage opens the scene that carries it, in the writing screen
/// of its project.
class SearchScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _field = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = const <SearchResult>[];
  bool _isSearching = false;
  bool _hasSearched = false;
  Object? _failure;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.all(scope.spacing.space24),
        children: <Widget>[
          const _SearchHeader(),
          SizedBox(height: scope.spacing.space16),
          LimpidSearchField(
            controller: _field,
            hint: strings.searchFieldHint,
            semanticLabel: strings.searchFieldLabel,
            clearTooltip: strings.searchClear,
            autofocus: true,
            onChanged: _onChanged,
          ),
          SizedBox(height: scope.spacing.space24),
          _body(),
        ],
      ),
    );
  }

  /// The body of the screen: the passages, or the state that explains why
  /// there is none.
  Widget _body() {
    final AppLocalizations strings = AppLocalizations.of(context);
    if (_isSearching) {
      return const Center(child: LimpidSpinner(size: LimpidSpinnerSize.large));
    }
    if (_failure != null) {
      return LimpidEmptyState(
        title: strings.searchFailureTitle,
        message: strings.searchFailureMessage,
        action: LimpidButton(
          label: strings.searchRetry,
          icon: LimpidIcons.sync,
          onPressed: () => _onChanged(_field.text),
        ),
      );
    }
    if (!_hasSearched) {
      return LimpidEmptyState(
        title: strings.searchIdleTitle,
        message: strings.searchIdleMessage,
      );
    }
    if (_results.isEmpty) {
      return LimpidEmptyState(
        title: strings.searchEmptyTitle,
        message: strings.searchEmptyMessage,
      );
    }
    return _Results(results: _results, onOpen: _open);
  }

  /// Searches the manuscript when the author types.
  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = const <SearchResult>[];
        _isSearching = false;
        _hasSearched = false;
        _failure = null;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(_searchDelay, () => unawaited(_search(query)));
  }

  /// Runs the search and shows its passages.
  Future<void> _search(String query) async {
    try {
      final List<SearchResult> results = await ref
          .read(searchRepositoryProvider)
          .search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
        _hasSearched = true;
        _failure = null;
      });
    } on Object catch (failure) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _hasSearched = true;
        _failure = failure;
      });
    }
  }

  /// Opens the scene that carries the passage.
  void _open(SearchResult result) {
    unawaited(openSearchResult(context: context, ref: ref, result: result));
  }
}

/// The header of the search screen.
class _SearchHeader extends StatelessWidget {
  /// Creates the header.
  const _SearchHeader();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.searchTitle,
          style: textTheme.headlineMedium?.copyWith(
            color: scope.colors.fgDefault,
            fontWeight: FontWeight.w600,
            fontFamily: LimpidFontFamily.display,
          ),
        ),
        SizedBox(height: scope.spacing.space4),
        Text(
          strings.searchSubtitle,
          style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
        ),
      ],
    );
  }
}

/// The passages a search found.
class _Results extends StatelessWidget {
  /// Creates the list of passages.
  const _Results({required this.results, required this.onOpen});

  /// The passages the search found.
  final List<SearchResult> results;

  /// Called when the author picks a passage.
  final ValueChanged<SearchResult> onOpen;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          strings.searchResultCount(results.length),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
        ),
        SizedBox(height: scope.spacing.space8),
        for (final SearchResult result in results) ...<Widget>[
          SearchResultTile(result: result, onTap: () => onOpen(result)),
          SizedBox(height: scope.spacing.space4),
        ],
      ],
    );
  }
}
