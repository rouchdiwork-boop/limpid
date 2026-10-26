import 'package:flutter/material.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The table of contents of a published book.
///
/// The list carries the chapters of the book and, under each of them, the
/// excerpt of every scene. It never carries the whole text of a manuscript.
class PublicationTableOfContents extends StatelessWidget {
  /// Creates the table of contents.
  const PublicationTableOfContents({required this.chapters, super.key});

  /// The chapters of the book, in reading order.
  final List<PublicationChapter> chapters;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;

    if (chapters.isEmpty) {
      return LimpidEmptyState(
        title: strings.editorOutlineEmpty,
        icon: LimpidIcons.empty,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.publicationContents,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: scope.spacing.space16),
        for (int index = 0; index < chapters.length; index++) ...<Widget>[
          PublicationChapterSection(
            chapter: chapters[index],
            number: index + 1,
          ),
          if (index < chapters.length - 1)
            SizedBox(height: scope.spacing.space24),
        ],
      ],
    );
  }
}

/// A chapter of a published book, with the excerpt of every scene.
class PublicationChapterSection extends StatelessWidget {
  /// Creates the section of a chapter.
  const PublicationChapterSection({
    required this.chapter,
    required this.number,
    super.key,
  });

  /// The chapter displayed by the section.
  final PublicationChapter chapter;

  /// The rank of the chapter in the book, starting at one.
  final int number;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: scope.spacing.space24,
              child: Text(
                '$number',
                style: textTheme.labelSmall?.copyWith(
                  color: scope.colors.fgSubtle,
                  fontFamily: LimpidFontFamily.mono,
                ),
              ),
            ),
            Expanded(
              child: Text(
                chapter.title,
                style: textTheme.titleMedium?.copyWith(
                  color: scope.colors.fgDefault,
                  fontFamily: LimpidFontFamily.display,
                ),
              ),
            ),
          ],
        ),
        if (chapter.synopsis.isNotEmpty) ...<Widget>[
          SizedBox(height: scope.spacing.space8),
          Text(
            chapter.synopsis,
            style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
          ),
        ],
        SizedBox(height: scope.spacing.space12),
        for (final PublicationScene scene in chapter.scenes) ...<Widget>[
          PublicationSceneExcerpt(scene: scene),
          SizedBox(height: scope.spacing.space16),
        ],
      ],
    );
  }
}

/// The excerpt of a scene of a published book.
class PublicationSceneExcerpt extends StatelessWidget {
  /// Creates the excerpt of a scene.
  const PublicationSceneExcerpt({required this.scene, super.key});

  /// The scene displayed by the widget.
  final PublicationScene scene;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            LimpidTag(label: strings.publicationExcerpt),
            if (scene.title.isNotEmpty) ...<Widget>[
              SizedBox(width: scope.spacing.space8),
              Expanded(
                child: Text(
                  scene.title,
                  style: textTheme.labelLarge?.copyWith(
                    color: scope.colors.fgMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (scene.hasExcerpt) ...<Widget>[
          SizedBox(height: scope.spacing.space8),
          Text(
            scene.excerpt,
            style: textTheme.bodyLarge?.copyWith(
              color: scope.colors.fgDefault,
              fontFamily: LimpidFontFamily.manuscript,
              height: 1.75,
            ),
          ),
        ],
      ],
    );
  }
}
