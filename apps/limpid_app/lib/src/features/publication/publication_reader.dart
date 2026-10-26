import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/publication_repository.dart';
import 'package:limpid_app/src/features/dashboard/dashboard_providers.dart';
import 'package:limpid_app/src/features/publication/publication_chapters.dart';
import 'package:limpid_app/src/features/publication/publication_providers.dart';
import 'package:limpid_app/src/features/publication/publication_routes.dart';
import 'package:limpid_app/src/features/publication/publication_states.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The reading page of a published book.
///
/// The visitor walks through the chapters of the book and reads the excerpt
/// of every scene. The page is a reading, never an editing: there is no
/// editor and nothing can be changed.
class PublicationReaderScreen extends ConsumerWidget {
  /// Creates the reading page of a book.
  const PublicationReaderScreen({required this.projectId, super.key});

  /// The identifier of the project.
  final String projectId;

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
              _ReaderBody(
                project: project,
                chapters: chapters,
                authorName: ref.watch(authorNameProvider),
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

/// The body of the reading page.
class _ReaderBody extends StatelessWidget {
  const _ReaderBody({
    required this.project,
    required this.chapters,
    required this.authorName,
  });

  final Project project;
  final List<PublicationChapter> chapters;
  final String authorName;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations strings = AppLocalizations.of(context);
    final LimpidThemeScope scope = context.limpid;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: EdgeInsets.all(scope.spacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              LimpidIconButton(
                icon: LimpidIcons.arrowLeft,
                tooltip: strings.projectPublicPage,
                size: LimpidButtonSize.large,
                onPressed: () => _goBack(context),
              ),
              SizedBox(width: scope.spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      project.title,
                      style: textTheme.titleMedium?.copyWith(
                        color: scope.colors.fgDefault,
                        fontFamily: LimpidFontFamily.display,
                      ),
                    ),
                    if (authorName.isNotEmpty)
                      Text(
                        authorName,
                        style: textTheme.bodySmall?.copyWith(
                          color: scope.colors.fgMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: scope.spacing.space24),
          if (chapters.isEmpty)
            LimpidEmptyState(
              title: strings.editorOutlineEmpty,
              icon: LimpidIcons.empty,
            )
          else
            for (int index = 0; index < chapters.length; index++) ...<Widget>[
              PublicationChapterSection(
                chapter: chapters[index],
                number: index + 1,
              ),
              if (index < chapters.length - 1)
                SizedBox(height: scope.spacing.space32),
            ],
        ],
      ),
    );
  }

  /// Leaves the reading page and goes back to the public page of the book.
  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(PublicationRoutes.showcase(project.id.value));
  }
}
