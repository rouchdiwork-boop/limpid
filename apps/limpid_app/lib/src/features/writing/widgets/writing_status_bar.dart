import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_app/src/features/revision/history/history_routes.dart';
import 'package:limpid_app/src/features/revision/presence_bar.dart';
import 'package:limpid_app/src/features/revision/presence_models.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The status bar of the writing screen.
///
/// It carries the figures of the scene being written — the number of words
/// and the reading time — the state of the automatic save and the peers
/// present on the scene. The figures are computed from the text itself,
/// never stored as a constant.
class WritingStatusBar extends StatelessWidget {
  /// Creates the status bar.
  const WritingStatusBar({
    required this.wordCount,
    required this.readingMinutes,
    required this.saveState,
    this.peers = const <PresencePeerView>[],
    this.documentId = '',
    super.key,
  });

  /// The number of words of the scene.
  final int wordCount;

  /// The reading time of the scene, in minutes.
  final int readingMinutes;

  /// The state of the automatic save.
  final EditorSaveState saveState;

  /// The peers present on the scene being written.
  final List<PresencePeerView> peers;

  /// The document of the scene being written.
  ///
  /// C'est lui qui porte l'historique des versions : quand il est vide — au
  /// demarrage, ou dans une scene qui n'a pas de document — l'historique
  /// n'est pas propose.
  final String documentId;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: scope.spacing.space16,
        vertical: scope.spacing.space8,
      ),
      decoration: BoxDecoration(
        color: scope.colors.bgSurface,
        border: Border(top: BorderSide(color: scope.colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          _Metric(
            icon: LimpidIcons.list,
            label: strings.writingWords(wordCount),
          ),
          SizedBox(width: scope.spacing.space16),
          _Metric(
            icon: LimpidIcons.clock,
            label: strings.writingReadingTime(readingMinutes),
          ),
          const Spacer(),
          if (documentId.isNotEmpty)
            LimpidIconButton(
              icon: LimpidIcons.timeline,
              tooltip: strings.historyTitle,
              size: LimpidButtonSize.small,
              onPressed: () => context.go(HistoryRoutes.detail(documentId)),
            ),
          if (documentId.isNotEmpty) SizedBox(width: scope.spacing.space12),
          PresenceBar(peers: peers),
          SizedBox(width: scope.spacing.space12),
          LimpidBadge(
            label: _saveLabel(strings),
            variant: _saveVariant(),
            showDot: saveState == EditorSaveState.idle,
          ),
        ],
      ),
    );
  }

  /// The label of the state of the automatic save.
  String _saveLabel(AppLocalizations strings) => switch (saveState) {
    EditorSaveState.idle => strings.editorAutosave,
    EditorSaveState.saving => strings.editorSaving,
    EditorSaveState.saved => strings.editorSaved,
    EditorSaveState.failed => strings.errorGeneric,
  };

  /// The variant of the state of the automatic save.
  LimpidStatusVariant _saveVariant() => switch (saveState) {
    EditorSaveState.idle => LimpidStatusVariant.neutral,
    EditorSaveState.saving => LimpidStatusVariant.info,
    EditorSaveState.saved => LimpidStatusVariant.success,
    EditorSaveState.failed => LimpidStatusVariant.danger,
  };
}

/// A figure of the manuscript, shown in the status bar.
class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: _iconSize, color: scope.colors.fgSubtle),
          SizedBox(width: scope.spacing.space6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scope.colors.fgSubtle),
          ),
        ],
      ),
    );
  }
}

/// The size of the icons of the status bar, in logical pixels.
const double _iconSize = 14;
