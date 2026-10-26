import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

void main() {
  group('WordCount', () {
    test('counts the words of a text', () {
      expect(WordCount.ofText('un deux trois'), 3);
      expect(WordCount.ofText('  un   deux  '), 2);
      expect(WordCount.ofText(''), 0);
      expect(WordCount.ofText('   '), 0);
    });

    test('counts the words of a content', () {
      expect(WordCount.ofContent(const TextContent('bonjour le monde')), 3);
    });

    test('counts the paragraphs of a text', () {
      expect(WordCount.paragraphsOf('un\n\ndeux\n\n\ntrois'), 3);
      expect(WordCount.paragraphsOf('un seul'), 1);
    });

    test('counts the characters without the trailing whitespace', () {
      expect(WordCount.charactersOf('abc  '), 3);
    });

    test('ignores the blocks that are not prose', () {
      final blocks = <Block>[
        _block(BlockType.paragraph, 'du texte'),
        _block(BlockType.heading1, 'Un titre'),
        _block(BlockType.listItem, 'un item'),
        _block(BlockType.code, 'code()'),
      ];
      expect(WordCount.ofBlocks(blocks), 4);
    });
  });

  group('ReadingTimeEstimator', () {
    test('estimates the reading time of a word count', () {
      const estimator = ReadingTimeEstimator();
      expect(estimator.estimate(0), Duration.zero);
      expect(estimator.estimate(200), const Duration(minutes: 1));
      expect(estimator.estimate(400), const Duration(minutes: 2));
    });

    test('honours a custom reading speed', () {
      const estimator = ReadingTimeEstimator(wordsPerMinute: 100);
      expect(estimator.estimate(300), const Duration(minutes: 3));
    });

    test('estimates the number of pages', () {
      const estimator = ReadingTimeEstimator();
      expect(estimator.estimatePages(0), 0);
      expect(estimator.estimatePages(301), 2);
    });
  });

  group('ProgressCalculator', () {
    const calculator = ProgressCalculator();

    test('computes the progress of a scene', () {
      final progress = calculator.forScene(
        wordCount: 500,
        targetWordCount: 1000,
      );
      expect(progress.ratio, 0.5);
      expect(progress.isCompleted, isFalse);
    });

    test('caps the ratio at one', () {
      final progress = calculator.forScene(
        wordCount: 1500,
        targetWordCount: 1000,
      );
      expect(progress.ratio, 1);
      expect(progress.isCompleted, isTrue);
    });

    test('returns a zero ratio when there is no target', () {
      final progress = calculator.forScene(wordCount: 500, targetWordCount: 0);
      expect(progress.ratio, 0);
      expect(progress.isCompleted, isFalse);
    });

    test('aggregates the scenes into a chapter', () {
      final scenes = <SceneProgress>[
        calculator.forScene(wordCount: 400, targetWordCount: 500),
        calculator.forScene(wordCount: 600, targetWordCount: 500),
      ];
      final chapter = calculator.forChapter(scenes: scenes);
      expect(chapter.wordCount, 1000);
      expect(chapter.targetWordCount, 1000);
      expect(chapter.sceneCount, 2);
      expect(chapter.completedSceneCount, 1);
      expect(chapter.ratio, 1);
    });

    test('aggregates the chapters into a volume', () {
      final chapters = <ChapterProgress>[
        calculator.forChapter(
          scenes: <SceneProgress>[
            calculator.forScene(wordCount: 100, targetWordCount: 100),
          ],
        ),
        calculator.forChapter(
          scenes: <SceneProgress>[
            calculator.forScene(wordCount: 50, targetWordCount: 100),
          ],
        ),
      ];
      final volume = calculator.forVolume(chapters: chapters);
      expect(volume.wordCount, 150);
      expect(volume.chapterCount, 2);
      expect(volume.completedChapterCount, 1);
      expect(volume.ratio, 0.75);
    });

    test('aggregates the volumes into a series', () {
      final volumes = <VolumeProgress>[
        calculator.forVolume(
          chapters: <ChapterProgress>[
            calculator.forChapter(
              scenes: <SceneProgress>[
                calculator.forScene(wordCount: 100, targetWordCount: 100),
              ],
            ),
          ],
        ),
      ];
      final series = calculator.forSeries(volumes: volumes);
      expect(series.wordCount, 100);
      expect(series.volumeCount, 1);
      expect(series.completedVolumeCount, 1);
      expect(series.ratio, 1);
    });
  });

  group('GoalEvaluator', () {
    const evaluator = GoalEvaluator();

    test('evaluates the daily goal', () {
      final status = evaluator.evaluateDaily(
        writtenWords: 600,
        dailyWordTarget: 1000,
      );
      expect(status.ratio, 0.6);
      expect(status.isReached, isFalse);
      expect(status.remainingWords, 400);
    });

    test('reports a reached goal', () {
      final status = evaluator.evaluateDaily(
        writtenWords: 1200,
        dailyWordTarget: 1000,
      );
      expect(status.isReached, isTrue);
      expect(status.remainingWords, 0);
      expect(status.ratio, 1);
    });

    test('returns a neutral status without a target', () {
      final status = evaluator.evaluateDaily(
        writtenWords: 1200,
        dailyWordTarget: 0,
      );
      expect(status.ratio, 0);
      expect(status.isReached, isFalse);
    });

    test('counts the consecutive writing days', () {
      final today = DateTime(2026, 10, 25);
      final streak = evaluator.evaluateStreak(
        writingDays: <DateTime>[
          DateTime(2026, 10, 25),
          DateTime(2026, 10, 24),
          DateTime(2026, 10, 23),
          DateTime(2026, 10, 20),
        ],
        today: today,
      );
      expect(streak, 3);
    });

    test('counts a streak that ended yesterday', () {
      final streak = evaluator.evaluateStreak(
        writingDays: <DateTime>[DateTime(2026, 10, 24), DateTime(2026, 10, 23)],
        today: DateTime(2026, 10, 25),
      );
      expect(streak, 2);
    });

    test('returns zero without any writing day', () {
      final streak = evaluator.evaluateStreak(
        writingDays: const <DateTime>[],
        today: DateTime(2026, 10, 25),
      );
      expect(streak, 0);
    });
  });

  group('PlanDefinition', () {
    test('describes the free plan', () {
      const plan = PlanDefinition.free;
      expect(plan.priceInCents, 0);
      expect(plan.quota.maxProjects, 1);
      expect(plan.quota.maxWords, 10000);
      expect(plan.allowsProjectCount(1), isTrue);
      expect(plan.allowsProjectCount(2), isFalse);
    });

    test('describes the studio plan', () {
      const plan = PlanDefinition.studio;
      expect(plan.quota.maxSeats, 5);
      expect(plan.hasLocalAi, isTrue);
      expect(plan.hasApiAccess, isTrue);
      expect(plan.isUnlimitedProjects, isTrue);
    });

    test('returns the definition of a plan', () {
      expect(PlanDefinition.of(SubscriptionPlan.pro), PlanDefinition.pro);
    });
  });

  group('ExportFormat', () {
    test('exposes a file extension for every format', () {
      expect(ExportFormat.epub3.fileExtension, 'epub');
      expect(ExportFormat.docx.fileExtension, 'docx');
      expect(ExportFormat.kindleKpf.fileExtension, 'kpf');
    });

    test('exposes a mime type for every format', () {
      expect(mimeTypeOf(ExportFormat.epub3), 'application/epub+zip');
      expect(mimeTypeOf(ExportFormat.markdown), 'text/markdown');
    });

    test('flags the print ready formats', () {
      expect(ExportFormat.pdfPrintReady.isPrintReady, isTrue);
      expect(ExportFormat.kindleKpf.isPrintReady, isTrue);
      expect(ExportFormat.pdfReflowable.isPrintReady, isFalse);
    });
  });

  group('domain entities', () {
    test('copyWith replaces a field without mutating the original', () {
      const project = Project(
        id: ProjectId('p1'),
        ownerId: AuthorId('a1'),
        title: 'Titre',
        order: OrderKey.initial,
      );
      final renamed = project.copyWith(title: 'Nouveau titre');
      expect(project.title, 'Titre');
      expect(renamed.title, 'Nouveau titre');
      expect(renamed.id, project.id);
    });

    test('supports equality on the value fields', () {
      const a = Author(
        id: AuthorId('a1'),
        displayName: 'Rouchdi',
        email: 'r@example.com',
      );
      const b = Author(
        id: AuthorId('a1'),
        displayName: 'Rouchdi',
        email: 'r@example.com',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('builds a rich content from a delta', () {
      final content = InlineContent.fromDeltaJson(
        '{"ops":[{"insert":"Bonjour"},{"insert":" le monde"}]}',
      );
      expect(content.plainText, 'Bonjour le monde');
      expect(content.isRich, isTrue);
    });

    test('rejects a malformed delta', () {
      expect(
        () => InlineContent.fromDeltaJson('not json'),
        throwsA(isA<InvalidContentException>()),
      );
      expect(
        () => InlineContent.fromDeltaJson('{"nope":1}'),
        throwsA(isA<InvalidContentException>()),
      );
    });

    test('keeps a comment thread immutable', () {
      const thread = CommentThread(
        id: CommentId('t1'),
        markId: MarkId('m1'),
        comments: <Comment>[],
      );
      final resolved = thread.copyWith(isResolved: true);
      expect(thread.isResolved, isFalse);
      expect(resolved.isResolved, isTrue);
    });
  });
}

/// Builds a block for the word count tests.
Block _block(BlockType type, String text) {
  return Block(
    id: BlockId('b-${text.hashCode}'),
    doc: const DocumentId('doc'),
    parent: null,
    order: OrderKey.initial,
    type: type,
    content: TextContent(text),
    lamport: 1,
    author: const AuthorId('a1'),
    version: 1,
  );
}
