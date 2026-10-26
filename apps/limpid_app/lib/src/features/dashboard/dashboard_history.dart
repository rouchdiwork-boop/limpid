import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_providers.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The history of the writing: the words written on each of the last days.
///
/// The history comes from the **sessions** of the writing: the days on
/// which the author wrote, and the words they wrote that day. A day
/// without writing is left out — the history shows what was written, not
/// what was touched.
///
/// The history is **local**: the sessions live on the device, and the panel
/// answers offline.
class DashboardHistory extends ConsumerWidget {
  /// Creates the card.
  const DashboardHistory({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final MaterialLocalizations dates = MaterialLocalizations.of(context);
    final List<WritingSession> sessions =
        ref.watch(writingSessionsProvider).value ?? const <WritingSession>[];

    return LimpidCard(
      title: strings.historyTitle,
      child: Padding(
        padding: EdgeInsets.only(top: scope.spacing.space16),
        child: sessions.isEmpty
            ? Text(
                strings.dataEmptyTitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: scope.colors.fgDefault),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final WritingSession session in sessions)
                    _HistoryLine(
                      day: session.day,
                      words: session.words,
                      dates: dates,
                    ),
                ],
              ),
      ),
    );
  }
}

/// A day of the history: its date and the words it carries.
class _HistoryLine extends StatelessWidget {
  /// Creates a line.
  const _HistoryLine({
    required this.day,
    required this.words,
    required this.dates,
  });

  /// The day of the session.
  final DateTime day;

  /// The number of words written that day.
  final int words;

  /// The dates of the interface, in the language of the author.
  final MaterialLocalizations dates;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Padding(
      padding: EdgeInsets.only(bottom: scope.spacing.space6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            dates.formatShortDate(day),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
          ),
          Text(
            strings.libraryWords(formatCount(words)),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scope.colors.fgDefault),
          ),
        ],
      ),
    );
  }
}
