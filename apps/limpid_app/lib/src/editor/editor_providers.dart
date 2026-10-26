import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_core/limpid_core.dart';

/// The outline of a project: its series, its tomes, its chapters and their
/// scenes.
///
/// The outline is read from the repository, level by level: the series of
/// the project, the tomes of every series, the chapters of every tome, and
/// the scenes of every chapter. The chapters that hang directly on the
/// project — the books that do not use the series and the tome levels — come
/// last.
final writingOutlineProvider = FutureProvider.family<WritingOutline, String>((
  Ref ref,
  String projectId,
) async {
  final ManuscriptRepository repository = ref.watch(
    manuscriptRepositoryProvider,
  );
  return readOutline(repository: repository, projectId: projectId);
});

/// Reads the hierarchy of [projectId] from [repository].
///
/// The function only reads the repository: it never writes it. The chapter
/// of the outline carries its number in the book, and the numbers follow the
/// reading order — the chapters of the tomes, then the chapters of the
/// project.
Future<WritingOutline> readOutline({
  required ManuscriptRepository repository,
  required String projectId,
}) async {
  final List<Series> series = await repository.listSeries(projectId);
  var chapterNumber = 0;

  Future<OutlineChapter> chapterOf(Chapter chapter) async {
    chapterNumber++;
    final List<Scene> scenes = await repository.listScenes(chapter.id.value);
    return OutlineChapter(
      chapter: chapter,
      scenes: <OutlineScene>[
        for (int index = 0; index < scenes.length; index++)
          OutlineScene(
            scene: scenes[index],
            chapterNumber: chapterNumber,
            sceneNumber: index + 1,
          ),
      ],
    );
  }

  final List<OutlineSeries> outlineSeries = <OutlineSeries>[];
  for (final Series item in series) {
    final List<Volume> volumes = await repository.listVolumes(item.id.value);
    final List<OutlineVolume> outlineVolumes = <OutlineVolume>[];
    for (final Volume volume in volumes) {
      final List<Chapter> chapters = await repository.listChaptersOfVolume(
        volume.id.value,
      );
      outlineVolumes.add(
        OutlineVolume(
          volume: volume,
          chapters: <OutlineChapter>[
            for (final Chapter chapter in chapters) await chapterOf(chapter),
          ],
        ),
      );
    }
    outlineSeries.add(OutlineSeries(series: item, volumes: outlineVolumes));
  }

  final List<OutlineChapter> direct = <OutlineChapter>[
    for (final Chapter chapter in await repository.listChapters(projectId))
      if (chapter.volumeId == null) await chapterOf(chapter),
  ];

  return WritingOutline(
    series: List<OutlineSeries>.unmodifiable(outlineSeries),
    chapters: List<OutlineChapter>.unmodifiable(direct),
  );
}

/// The state of the synchronisation, as the repository reports it.
///
/// The stream never throws: a broken synchronisation leaves the author
/// writing, the operations wait in the durable queue of the device.
final StreamProvider<SyncStatus> syncStatusProvider =
    StreamProvider<SyncStatus>((Ref ref) {
      final SyncRepository repository = ref.watch(syncRepositoryProvider);
      return repository.watch();
    });
