import 'package:flutter/material.dart';
import 'package:limpid_design_system/src/components/avatar.dart';
import 'package:limpid_design_system/src/components/status.dart';
import 'package:limpid_design_system/src/icons/limpid_icons.dart';
import 'package:limpid_design_system/src/theme/limpid_theme.dart';
import 'package:limpid_design_system/src/tokens/colors.dart';
import 'package:limpid_design_system/src/tokens/typography.dart';

/// The card of a scene, as displayed in the scene list of the editor.
class LimpidSceneCard extends StatelessWidget {
  /// Creates a scene card.
  const LimpidSceneCard({
    super.key,
    required this.title,
    required this.excerpt,
    required this.wordCount,
    this.onTap,
    this.status = LimpidStatusVariant.neutral,
    this.statusLabel,
    this.isSelected = false,
    this.trailing,
  });

  /// The title of the scene.
  final String title;

  /// The first words of the scene.
  final String excerpt;

  /// The number of words of the scene.
  final int wordCount;

  /// Called when the card is tapped.
  final VoidCallback? onTap;

  /// The status of the scene.
  final LimpidStatusVariant status;

  /// The label of the status.
  final String? statusLabel;

  /// Whether the scene is the one being edited.
  final bool isSelected;

  /// An optional trailing widget.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      selected: isSelected,
      child: Material(
        color: isSelected
            ? tokens.colors.accentSubtle
            : tokens.colors.bgSurface,
        borderRadius: BorderRadius.circular(tokens.radii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radii.md),
              border: Border.all(
                color: isSelected
                    ? tokens.colors.accentBorder
                    : tokens.colors.borderSubtle,
              ),
            ),
            padding: EdgeInsets.all(tokens.spacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall,
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                SizedBox(height: tokens.spacing.space8),
                Text(
                  excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.colors.fgMuted,
                  ),
                ),
                SizedBox(height: tokens.spacing.space12),
                Row(
                  children: <Widget>[
                    Text(
                      '$wordCount mots',
                      style: LimpidTypography.captionStyle(
                        color: tokens.colors.fgSubtle,
                      ),
                    ),
                    if (statusLabel != null) ...<Widget>[
                      SizedBox(width: tokens.spacing.space8),
                      LimpidBadge(label: statusLabel!, variant: status),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of the outline of a project.
///
/// The depth drives the indentation, which mirrors the hierarchy of the book.
class LimpidOutlineRow extends StatelessWidget {
  /// Creates an outline row.
  const LimpidOutlineRow({
    super.key,
    required this.title,
    required this.depth,
    this.wordCount,
    this.onTap,
    this.onToggleExpanded,
    this.isExpanded = true,
    this.hasChildren = false,
    this.isActive = false,
  });

  /// The label of the row.
  final String title;

  /// The depth of the row in the hierarchy, starting at 0.
  final int depth;

  /// The number of words of the row.
  final int? wordCount;

  /// Called when the row is tapped.
  final VoidCallback? onTap;

  /// Called when the disclosure triangle is tapped.
  final VoidCallback? onToggleExpanded;

  /// Whether the children of the row are visible.
  final bool isExpanded;

  /// Whether the row has children.
  final bool hasChildren;

  /// Whether the row is the one being edited.
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      selected: isActive,
      button: onTap != null,
      child: Material(
        color: isActive ? tokens.colors.accentSubtle : LimpidColors.transparent,
        borderRadius: BorderRadius.circular(tokens.radii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.only(
              left: tokens.spacing.space8 + depth * tokens.spacing.space16,
              right: tokens.spacing.space8,
              top: tokens.spacing.space6,
              bottom: tokens.spacing.space6,
            ),
            child: Row(
              children: <Widget>[
                if (hasChildren)
                  Semantics(
                    button: onToggleExpanded != null,
                    label: isExpanded ? 'Replier' : 'Déplier',
                    child: IconButton(
                      onPressed: onToggleExpanded,
                      tooltip: null,
                      iconSize: 18,
                      icon: Icon(
                        isExpanded
                            ? LimpidIcons.chevronDown
                            : LimpidIcons.chevronRight,
                        color: tokens.colors.fgMuted,
                      ),
                    ),
                  )
                else
                  SizedBox(width: tokens.spacing.space12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: isActive
                          ? tokens.colors.accent
                          : tokens.colors.fgDefault,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (wordCount != null) ...<Widget>[
                  SizedBox(width: tokens.spacing.space8),
                  Text(
                    '$wordCount',
                    style: LimpidTypography.captionStyle(
                      color: tokens.colors.fgSubtle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The preview of the cover of a book.
class LimpidCoverPreview extends StatelessWidget {
  /// Creates a cover preview.
  const LimpidCoverPreview({
    super.key,
    required this.title,
    this.author,
    this.image,
    this.width = 140,
    this.aspectRatio = 0.66,
  });

  /// The title of the book.
  final String title;

  /// The name of the author.
  final String? author;

  /// The image of the cover.
  final ImageProvider? image;

  /// The width of the preview, in logical pixels.
  final double width;

  /// The ratio between the width and the height of the cover.
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      image: image != null,
      label: 'Couverture de $title',
      child: Container(
        width: width,
        height: width / aspectRatio,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: tokens.colors.bgSunken,
          borderRadius: BorderRadius.circular(tokens.radii.sm),
          border: Border.all(color: tokens.colors.borderSubtle),
        ),
        child: image != null
            ? Image(image: image!, fit: BoxFit.cover)
            : Padding(
                padding: EdgeInsets.all(tokens.spacing.space12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall,
                    ),
                    if (author != null) ...<Widget>[
                      SizedBox(height: tokens.spacing.space8),
                      Text(
                        author!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LimpidTypography.captionStyle(
                          color: tokens.colors.fgMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

/// The meter displaying the word count of a manuscript against its goal.
class LimpidWordCountMeter extends StatelessWidget {
  /// Creates a word count meter.
  const LimpidWordCountMeter({
    super.key,
    required this.wordCount,
    required this.goal,
    this.label,
  });

  /// The current number of words.
  final int wordCount;

  /// The target number of words.
  final int goal;

  /// The label displayed above the meter.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final double ratio = goal <= 0 ? 0 : (wordCount / goal).clamp(0.0, 1.0);
    final int percentage = (ratio * 100).round();

    return Semantics(
      label: label,
      value: '$percentage%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              if (label != null)
                Text(label!, style: textTheme.labelMedium)
              else
                const SizedBox.shrink(),
              Text(
                '$wordCount / $goal',
                style: LimpidTypography.captionStyle(
                  color: tokens.colors.fgMuted,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.space6),
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radii.pill),
            child: LinearProgressIndicator(value: ratio),
          ),
        ],
      ),
    );
  }
}

/// The avatar of a character of the story bible.
class LimpidCharacterAvatar extends StatelessWidget {
  /// Creates a character avatar.
  const LimpidCharacterAvatar({
    super.key,
    required this.name,
    this.initials,
    this.image,
    this.role,
    this.isOnline = false,
    this.size = LimpidAvatarSize.medium,
  });

  /// The name of the character.
  final String name;

  /// The initials of the character.
  final String? initials;

  /// The portrait of the character.
  final ImageProvider? image;

  /// The role of the character in the story.
  final String? role;

  /// Whether the character is currently writing.
  final bool isOnline;

  /// The size of the avatar.
  final LimpidAvatarSize size;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope tokens = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final Widget avatar = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        LimpidAvatar(label: name, initials: initials, image: image, size: size),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: tokens.colors.success,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.colors.bgSurface, width: 2),
              ),
            ),
          ),
      ],
    );

    return Semantics(
      label: role == null ? name : '$name, $role',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          avatar,
          SizedBox(width: tokens.spacing.space8),
          Text(name, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
