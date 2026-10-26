/// Pure Dart core of Limpid: domain model, CRDT sync engine and business
/// rules.
///
/// This package is imported by the Flutter client **and** by the Dart API.
/// It must never import `package:flutter/*` and must not depend on anything
/// outside the Dart SDK.
library;

export 'src/domain/author.dart';
export 'src/domain/block.dart';
export 'src/domain/book_metadata.dart';
export 'src/domain/chapter.dart';
export 'src/domain/character.dart';
export 'src/domain/comment.dart';
export 'src/domain/content.dart';
export 'src/domain/cover.dart';
export 'src/domain/enums.dart';
export 'src/domain/export_format.dart';
export 'src/domain/export_job.dart';
export 'src/domain/ids.dart';
export 'src/domain/mark.dart';
export 'src/domain/place.dart';
export 'src/domain/plot_thread.dart';
export 'src/domain/project.dart';
export 'src/domain/scene.dart';
export 'src/domain/series.dart';
export 'src/domain/subscription_plan.dart';
export 'src/domain/timeline_event.dart';
export 'src/domain/volume.dart';
export 'src/errors.dart';
export 'src/rules/goal_evaluator.dart';
export 'src/rules/progress.dart';
export 'src/rules/reading_time.dart';
export 'src/rules/word_count.dart';
export 'src/sync/crdt_document.dart';
export 'src/sync/lamport_clock.dart';
export 'src/sync/ops.dart';
export 'src/sync/order_key.dart';
export 'src/sync/sync_engine.dart';
export 'src/sync/text_edit.dart';
export 'src/sync/three_way_merge.dart';
export 'src/sync/ulid.dart';
