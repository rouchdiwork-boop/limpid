import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:limpid_app/src/app/router.dart';
import 'package:limpid_app/src/domain/search_repository.dart';
import 'package:limpid_app/src/editor/editor_controller.dart';
import 'package:limpid_app/src/editor/editor_models.dart';
import 'package:limpid_app/src/editor/editor_providers.dart';

/// Opens the scene that carries [result].
///
/// The writing screen of the project of the passage is opened, and the scene
/// that holds the passage is selected: the writer lands on the passage, not
/// on the first scene of the book.
///
/// The navigation never throws: a scene that the outline does not hold — a
/// passage of a book that was deleted while the screen was open — leaves the
/// writing screen on its first scene.
Future<void> openSearchResult({
  required BuildContext context,
  required WidgetRef ref,
  required SearchResult result,
}) async {
  context.go(AppRoutes.writing(result.projectId));
  await _selectScene(ref, result);
}

/// Selects the scene of [result] in the writing screen of its project.
Future<void> _selectScene(WidgetRef ref, SearchResult result) async {
  if (result.sceneId.isEmpty) return;
  final WritingOutline outline = await ref.read(
    writingOutlineProvider(result.projectId).future,
  );
  OutlineScene? scene;
  for (final OutlineScene candidate in outline.scenes) {
    if (candidate.id.value != result.sceneId) continue;
    scene = candidate;
    break;
  }
  if (scene == null) return;
  await ref
      .read<WritingController>(
        writingControllerProvider(result.projectId).notifier,
      )
      .selectScene(scene);
}
