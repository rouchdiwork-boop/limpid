import 'package:limpid_ai/limpid_ai.dart';
import 'package:test/test.dart';

import 'helpers/fakes.dart';

void main() {
  group('BudgetGuard', () {
    test('refuse un appel qui dépasse le plafond par requête', () async {
      final FakeUsageMeter meter = FakeUsageMeter();
      final BudgetGuard guard = BudgetGuard(
        meter: meter,
        maxTokensPerRequest: 100,
      );

      await expectLater(
        guard.authorize(
          estimatedInputTokens: 80,
          estimatedOutputTokens: 40,
          userId: 'auteur-1',
          feature: 'rewrite_inline',
        ),
        throwsA(
          isA<AiBudgetExceeded>()
              .having(
                (AiBudgetExceeded error) => error.code,
                'code',
                'ai_budget_exceeded',
              )
              .having(
                (AiBudgetExceeded error) => error.limitKind,
                'limitKind',
                'request',
              )
              .having((AiBudgetExceeded error) => error.limit, 'limit', 100),
        ),
      );
    });

    test(
      'refuse un appel qui dépasse le plafond quotidien de tokens',
      () async {
        final FakeUsageMeter meter = FakeUsageMeter(
          current: const AiUsageSnapshot(
            totalTokens: 900,
            estimatedCostUsd: 0.2,
          ),
        );
        final BudgetGuard guard = BudgetGuard(
          meter: meter,
          maxTokensPerRequest: 1000,
          maxTokensPerDay: 1000,
        );

        await expectLater(
          guard.authorize(
            estimatedInputTokens: 60,
            estimatedOutputTokens: 60,
            userId: 'auteur-1',
            feature: 'query_book',
            taskKey: AiTaskKeys.queryBook,
          ),
          throwsA(
            isA<AiBudgetExceeded>().having(
              (AiBudgetExceeded error) => error.limitKind,
              'limitKind',
              'daily_tokens',
            ),
          ),
        );
      },
    );

    test('refuse un appel qui dépasse le plafond quotidien de coût', () async {
      final FakeUsageMeter meter = FakeUsageMeter(
        current: const AiUsageSnapshot(totalTokens: 10, estimatedCostUsd: 0.5),
      );
      final BudgetGuard guard = BudgetGuard(
        meter: meter,
        maxTokensPerRequest: 100000,
        maxCostPerDayUsd: 0.2,
      );

      await expectLater(
        guard.authorize(
          estimatedInputTokens: 1000,
          estimatedOutputTokens: 1000,
          userId: 'auteur-1',
          feature: 'generate_outline',
          model: AiModelCatalog.anthropicQuality,
        ),
        throwsA(
          isA<AiBudgetExceeded>().having(
            (AiBudgetExceeded error) => error.limitKind,
            'limitKind',
            'daily_cost',
          ),
        ),
      );
    });

    test('autorise un appel sous les plafonds', () async {
      final FakeUsageMeter meter = FakeUsageMeter(
        current: const AiUsageSnapshot(totalTokens: 10, estimatedCostUsd: 0),
      );
      final BudgetGuard guard = BudgetGuard(
        meter: meter,
        maxTokensPerRequest: 1000,
        maxTokensPerDay: 10000,
      );

      await guard.authorize(
        estimatedInputTokens: 100,
        estimatedOutputTokens: 200,
        userId: 'auteur-1',
        feature: 'summarize',
      );

      expect(meter.recorded, isEmpty);
    });

    test('enregistre la consommation réelle', () async {
      final FakeUsageMeter meter = FakeUsageMeter();
      final BudgetGuard guard = BudgetGuard(
        meter: meter,
        maxTokensPerRequest: 1000,
      );

      await guard.record(
        const AiUsage(inputTokens: 30, outputTokens: 12),
        userId: 'auteur-1',
        feature: 'rewrite_inline',
        taskKey: AiTaskKeys.rewriteInline,
        provider: AiProviderKind.anthropic,
      );

      expect(meter.recorded, hasLength(1));
      expect(meter.recorded.single.totalTokens, 42);
      expect(meter.recordedFeatures.single, 'rewrite_inline');
    });
  });
}
