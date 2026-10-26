import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_design_system/limpid_design_system.dart';
import 'package:limpid_quill/limpid_quill.dart' show kMinimumTapTarget;

/// The size of the icons of the toolbar, in logical pixels.
const double _kIconSize = 16;

/// The toolbar of the writing screen.
///
/// It carries the destinations of the studio, the switches of the editor —
/// the plan, the reading mode and the assistant — and the state of the
/// synchronisation.
class WritingToolbar extends StatelessWidget {
  /// Creates the toolbar.
  const WritingToolbar({
    required this.syncStatus,
    required this.isReadMode,
    required this.isAssistantVisible,
    required this.isRevisionVisible,
    required this.onTogglePlan,
    required this.onToggleAssistant,
    required this.onToggleRevision,
    required this.onToggleReadMode,
    super.key,
  });

  /// The state of the synchronisation, `null` when it is unknown.
  final SyncStatus? syncStatus;

  /// Whether the manuscript is displayed instead of being edited.
  final bool isReadMode;

  /// Whether the assistant panel is open.
  final bool isAssistantVisible;

  /// Whether the panel of the review is open.
  final bool isRevisionVisible;

  /// Called when the plan is shown or hidden.
  final VoidCallback onTogglePlan;

  /// Called when the assistant panel is shown or hidden.
  final VoidCallback onToggleAssistant;

  /// Called when the panel of the review is shown or hidden.
  final VoidCallback onToggleRevision;

  /// Called when the reading mode is entered or left.
  final VoidCallback onToggleReadMode;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    return Container(
      constraints: const BoxConstraints(minHeight: kMinimumTapTarget),
      padding: EdgeInsets.symmetric(horizontal: scope.spacing.space12),
      decoration: BoxDecoration(
        color: scope.colors.bgSurface,
        border: Border(bottom: BorderSide(color: scope.colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          // Les destinations du studio défilent quand la barre est trop
          // étroite : les bascules de l'éditeur, elles, restent visibles.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _ToolbarAction(
                    label: strings.writingPlan,
                    icon: LimpidIcons.tree,
                    onPressed: onTogglePlan,
                  ),
                  _ToolbarAction(
                    label: strings.writingManuscript,
                    icon: LimpidIcons.pen,
                    isActive: true,
                  ),
                  _ToolbarAction(
                    label: strings.writingReview,
                    icon: LimpidIcons.book,
                    isActive: isRevisionVisible,
                    onPressed: onToggleRevision,
                  ),
                  _ToolbarAction(
                    label: strings.writingBible,
                    icon: LimpidIcons.bible,
                  ),
                ],
              ),
            ),
          ),
          _ToolbarAction(
            label: strings.editorReadMode,
            icon: LimpidIcons.book,
            isActive: isReadMode,
            onPressed: onToggleReadMode,
          ),
          _ToolbarAction(
            label: strings.editorAiTitle,
            icon: LimpidIcons.sparkles,
            isActive: isAssistantVisible,
            onPressed: onToggleAssistant,
          ),
          SizedBox(width: scope.spacing.space8),
          _SyncPill(status: syncStatus),
        ],
      ),
    );
  }
}

/// A destination of the studio, or a switch of the editor.
class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.label,
    required this.icon,
    this.isActive = false,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final bool isEnabled = onPressed != null;
    final Color foreground = isActive
        ? scope.colors.accent
        : (isEnabled ? scope.colors.fgMuted : scope.colors.fgSubtle);

    return Semantics(
      button: true,
      enabled: isEnabled,
      selected: isActive,
      label: label,
      child: Material(
        color: isActive ? scope.colors.accentSubtle : LimpidColors.transparent,
        borderRadius: BorderRadius.circular(scope.radii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: kMinimumTapTarget),
            padding: EdgeInsets.symmetric(horizontal: scope.spacing.space8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: _kIconSize, color: foreground),
                SizedBox(width: scope.spacing.space6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The pill displaying the state of the synchronisation.
class _SyncPill extends StatelessWidget {
  const _SyncPill({required this.status});

  final SyncStatus? status;

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return const SizedBox.shrink();
    }
    return LimpidSyncStatusPill(status: _pillStatus(status!));
  }

  /// The state of the design system matching a state of the repository.
  static LimpidSyncStatus _pillStatus(SyncStatus status) => switch (status) {
    SyncStatus.synced => LimpidSyncStatus.synced,
    SyncStatus.syncing => LimpidSyncStatus.syncing,
    SyncStatus.offline => LimpidSyncStatus.offline,
    SyncStatus.conflict => LimpidSyncStatus.error,
  };
}
