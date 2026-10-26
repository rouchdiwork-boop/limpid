import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_core/limpid_core.dart';

/// The outline of a project: its chapters and their scenes.
///
/// The outline is read from the repository, chapter by chapter: the scenes
/// of a chapter are needed to build the plan of the book.
final writingOutlineProvider = FutureProvider.family<WritingOutline, String>((
  Ref ref,
  String projectId,
) async {
  final ManuscriptRepository repository = ref.watch(
    manuscriptRepositoryProvider,
  );
  final List<Chapter> chapters = await repository.listChapters(projectId);

  final List<OutlineChapter> outline = <OutlineChapter>[];
  for (int index = 0; index < chapters.length; index++) {
    final Chapter chapter = chapters[index];
    final List<Scene> scenes = await repository.listScenes(chapter.id.value);
    outline.add(
      OutlineChapter(
        chapter: chapter,
        scenes: <OutlineScene>[
          for (int sceneIndex = 0; sceneIndex < scenes.length; sceneIndex++)
            OutlineScene(
              scene: scenes[sceneIndex],
              chapterNumber: index + 1,
              sceneNumber: sceneIndex + 1,
            ),
        ],
      ),
    );
  }

  return WritingOutline(chapters: List<OutlineChapter>.unmodifiable(outline));
});

/// The state of the synchronisation, as the repository reports it.
///
/// The stream never throws: a broken synchronisation leaves the author
/// writing, the operations wait in the durable queue of the device.
final StreamProvider<SyncStatus> syncStatusProvider =
    StreamProvider<SyncStatus>((Ref ref) {
      final SyncRepository repository = ref.watch(syncRepositoryProvider);
      return repository.watch();
    });
