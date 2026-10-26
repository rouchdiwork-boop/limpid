import 'package:flutter/material.dart';
import 'package:limpid_app/src/features/revision/presence_models.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The size of the icons of the bar, in logical pixels.
const double _kIconSize = 14;

/// The bar of the presence: the peers present on the document.
///
/// The bar shows an avatar per peer, and the paragraph the caret of the peer
/// stands in. The relay owns the presence — the bar only displays it.
///
/// The label is optional: the panel of the review names the peers, the
/// status bar of the editor leaves the room to the manuscript.
class PresenceBar extends StatelessWidget {
  /// Creates the bar.
  const PresenceBar({required this.peers, this.label, super.key});

  /// The peers present on the document.
  final List<PresencePeerView> peers;

  /// The name of the row, `null` when the bar shows the peers alone.
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) return const SizedBox.shrink();

    final LimpidThemeScope tokens = context.limpid;
    final String? name = label;

    final Widget avatars = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final PresencePeerView peer in peers) ...<Widget>[
            _Peer(peer: peer),
            SizedBox(width: tokens.spacing.space8),
          ],
        ],
      ),
    );

    if (name == null) return avatars;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.space16,
        tokens.spacing.space8,
        tokens.spacing.space16,
        tokens.spacing.space8,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            LimpidIcons.users,
            size: _kIconSize,
            color: tokens.colors.fgSubtle,
          ),
          SizedBox(width: tokens.spacing.space6),
          Text(
            name,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: tokens.colors.fgSubtle),
          ),
          SizedBox(width: tokens.spacing.space8),
          Expanded(child: avatars),
        ],
      ),
    );
  }
}

/// A peer of the presence bar: its avatar and the position of its caret.
class _Peer extends StatelessWidget {
  const _Peer({required this.peer});

  /// The peer shown by the row.
  final PresencePeerView peer;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final int? paragraph = peer.paragraph;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Tooltip(
          message: peer.displayName,
          child: LimpidAvatar(
            label: peer.displayName,
            size: LimpidAvatarSize.small,
            semanticLabel: peer.displayName,
          ),
        ),
        if (paragraph != null) ...<Widget>[
          SizedBox(width: tokens.spacing.space4),
          LimpidBadge(label: '¶ $paragraph'),
        ],
      ],
    );
  }
}
