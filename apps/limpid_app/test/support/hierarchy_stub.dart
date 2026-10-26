import 'package:limpid_core/limpid_core.dart';

/// La hiérarchie du livre qu'une doublure ne sait pas faire.
///
/// Les doublures qui ne mesurent pas la hiérarchie l'utilisent : elles
/// répondent une liste vide et refusent d'écrire. Les doublures qui doivent
/// la mesurer — le plan du livre, la hiérarchie elle-même — l'implémentent
/// pour de bon.
abstract class StubHierarchyRepository {
  /// Les séries du projet : aucune.
  Future<List<Series>> listSeries(String projectId) async => const <Series>[];

  /// La doublure ne crée pas de série.
  Future<Series> createSeries({
    required String projectId,
    required String title,
    String synopsis = '',
  }) async => throw UnimplementedError('The fake does not create series.');

  /// Les tomes de la série : aucun.
  Future<List<Volume>> listVolumes(String seriesId) async => const <Volume>[];

  /// La doublure ne crée pas de tome.
  Future<Volume> createVolume({
    required String seriesId,
    required String title,
    String synopsis = '',
  }) async => throw UnimplementedError('The fake does not create volumes.');

  /// Les chapitres du tome : aucun.
  Future<List<Chapter>> listChaptersOfVolume(String volumeId) async =>
      const <Chapter>[];

  /// La doublure ne crée pas de chapitre.
  Future<Chapter> createChapter({
    required String projectId,
    String? volumeId,
    required String title,
    String synopsis = '',
  }) async => throw UnimplementedError('The fake does not create chapters.');

  /// La doublure ne crée pas de scène.
  Future<Scene> createScene({
    required String chapterId,
    required String title,
    String synopsis = '',
  }) async => throw UnimplementedError('The fake does not create scenes.');

  /// La doublure ne déplace pas de scène.
  Future<Scene> moveScene({
    required String sceneId,
    required int targetIndex,
  }) async => throw UnimplementedError('The fake does not move scenes.');
}
