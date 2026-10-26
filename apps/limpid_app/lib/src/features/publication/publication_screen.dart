import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/editor/editor_statistics.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_providers.dart';
import 'package:limpid_app/src/features/projects/formatters.dart';
import 'package:limpid_app/src/features/projects/project_cover.dart';
import 'package:limpid_app/src/features/projects/project_metrics.dart';
import 'package:limpid_app/src/features/publication/publication_chapters.dart';
import 'package:limpid_app/src/features/publication/publication_providers.dart';
import 'package:limpid_app/src/features/publication/publication_routes.dart';
import 'package:limpid_app/src/features/publication/publication_states.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The width under which the public page of a book is a single column.
const double publicationWideLayoutBreakpoint = 900;

/// The width of the cover of a book on a wide screen.
const double publicationCoverWidth = 280;

/// The width of the cover of a book on a narrow screen.
const double publicationNarrowCoverWidth = 160;

/// The key of the cover of the public page.
const Key publicationCoverKey = Key('publication-cover');

/// The key of the table of contents of the public page.
const Key publicationTableOfContentsKey = Key('publication-table-of-contents');

/// The key of the title of the public page.
const Key publicationTitleKey = Key('publication-title');

/// The key of the summary of the public page.
const Key publicationSummaryKey = Key('publication-summary');

/// The public page of a book.
///
/// The page shows the cover, the title, the synopsis, the author and the
/// chapters of the book with the excerpt of every scene. It reads the local
/// repository: a published book of the author is displayed with its real
/// data, and a book that is not published has no page at all.
class PublicationScreen extends ConsumerWidget {
  /// Creates the public page of a book.
  const PublicationScreen({
    required this.projectId,
    this.onOpenReader,
    super.key,
  });

  /// The identifier of the project.
  final String projectId;

  /// Called when the reader asks to open the reading page of the book.
  ///
  /// When it is null, the screen navigates to the reading route of the
  /// application.
  final ValueChanged<String>? onOpenReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Publication> publication = ref.watch(
      publicationProvider(projectId),
    );

    return Scaffold(
      body: SafeArea(
        child: publication.when(
          loading: () => const PublicationLoading(),
          error: (Object error, StackTrace stackTrace) => PublicationFailure(
            onRetry: () => ref.invalidate(publicationProvider(projectId)),
          ),
          data: (Publication data) => switch (data) {
            PublishedBook(
              :final Project project,
              :final List<PublicationChapter> chapters,
            ) =>
              _PublishedView(
                project: project,
                chapters: chapters,
                authorName: ref.watch(authorNameProvider),
                onOpenReader: onOpenReader,
              ),
            UnpublishedBook(:final Project project) => PublicationUnavailable(
              project: project,
            ),
            UnknownBook() => const PublicationUnavailable(),
          },
        ),
      ),
    );
  }
}

/// The layout of the public page of a published book.
class _PublishedView extends StatelessWidget {
  const _PublishedView({
    required this.project,
    required this.chapters,
    required this.authorName,
    this.onOpenReader,
  });

  final Project project;
  final List<PublicationChapter> chapters;
  final String authorName;
  final ValueChanged<String>? onOpenReader;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide =
            constraints.maxWidth >= publicationWideLayoutBreakpoint;
        final Widget cover = _PublicationCoverPane(
          key: publicationCoverKey,
          project: project,
          chapters: chapters,
          authorName: authorName,
          width: isWide ? publicationCoverWidth : publicationNarrowCoverWidth,
          onOpenReader: onOpenReader,
        );
        final Widget summary = _PublicationSummary(
          key: publicationSummaryKey,
          project: project,
          authorName: authorName,
        );
        final Widget table = PublicationTableOfContents(
          key: publicationTableOfContentsKey,
          chapters: chapters,
        );

        if (!isWide) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(scope.spacing.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                cover,
                SizedBox(height: scope.spacing.space24),
                summary,
                SizedBox(height: scope.spacing.space32),
                table,
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: EdgeInsets.all(scope.spacing.space32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(width: publicationCoverWidth, child: cover),
              SizedBox(width: scope.spacing.space32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    summary,
                    SizedBox(height: scope.spacing.space32),
                    table,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The cover of the book, with the figures of the public page.
class _PublicationCoverPane extends StatelessWidget {
  const _PublicationCoverPane({
    required this.project,
    required this.chapters,
    required this.authorName,
    required this.width,
    this.onOpenReader,
    super.key,
  });

  final Project project;
  final List<PublicationChapter> chapters;
  final String authorName;
  final double width;
  final ValueChanged<String>? onOpenReader;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final int words = chapters.fold<int>(
      0,
      (int total, PublicationChapter chapter) => total + chapter.wordCount,
    );
    final int minutes = readingMinutesOf(words);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ProjectCover(
          title: project.title,
          author: authorName,
          seed: coverSeedOf(project.id.value),
          width: width,
        ),
        SizedBox(height: scope.spacing.space16),
        Wrap(
          spacing: scope.spacing.space8,
          runSpacing: scope.spacing.space8,
          children: <Widget>[
            LimpidBadge(
              label: publicationStatusLabel(strings, project.status),
              variant: publicationStatusVariant(project.status),
            ),
            LimpidBadge(label: strings.projectChapterCount(chapters.length)),
          ],
        ),
        SizedBox(height: scope.spacing.space12),
        Text(
          strings.libraryWords(formatCount(words)),
          style: textTheme.bodySmall?.copyWith(color: scope.colors.fgMuted),
        ),
        Text(
          strings.writingReadingTime(minutes),
          style: textTheme.bodySmall?.copyWith(color: scope.colors.fgSubtle),
        ),
        SizedBox(height: scope.spacing.space16),
        LimpidButton(
          label: strings.publicationRead,
          icon: LimpidIcons.book,
          size: LimpidButtonSize.large,
          expand: true,
          onPressed: () => _openReader(context),
        ),
      ],
    );
  }

  /// Opens the reading page of the book.
  void _openReader(BuildContext context) {
    final ValueChanged<String>? callback = onOpenReader;
    if (callback != null) {
      callback(project.id.value);
      return;
    }
    context.go(PublicationRoutes.reader(project.id.value));
  }
}

/// The title, the author and the synopsis of the book.
class _PublicationSummary extends StatelessWidget {
  const _PublicationSummary({
    required this.project,
    required this.authorName,
    super.key,
  });

  final Project project;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          project.title,
          key: publicationTitleKey,
          style: textTheme.headlineMedium?.copyWith(
            color: scope.colors.fgDefault,
            fontFamily: LimpidFontFamily.display,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (authorName.isNotEmpty) ...<Widget>[
          SizedBox(height: scope.spacing.space8),
          Row(
            children: <Widget>[
              Icon(LimpidIcons.user, size: 16, color: scope.colors.fgMuted),
              SizedBox(width: scope.spacing.space8),
              Expanded(
                child: Text(
                  authorName,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scope.colors.fgMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (project.synopsis.isNotEmpty) ...<Widget>[
          SizedBox(height: scope.spacing.space16),
          Text(
            project.synopsis,
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
