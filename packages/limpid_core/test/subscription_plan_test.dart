import 'package:limpid_core/limpid_core.dart';
import 'package:test/test.dart';

void main() {
  group('PlanQuota', () {
    test('caps no token when the field is left out', () {
      const PlanQuota quota = PlanQuota(
        maxProjects: 1,
        maxWords: 10000,
        maxExportsPerMonth: 50,
        maxStorageBytes: 100,
        maxSeats: 1,
        dailyAiRewrites: 2,
        monthlyAiCovers: 0,
      );

      expect(quota.monthlyAiTokens, 0);
    });

    test('tells two quotas apart on their tokens', () {
      const PlanQuota capped = PlanQuota(
        maxProjects: 1,
        maxWords: 10000,
        maxExportsPerMonth: 50,
        maxStorageBytes: 100,
        maxSeats: 1,
        dailyAiRewrites: 2,
        monthlyAiCovers: 0,
        monthlyAiTokens: 500000,
      );
      const PlanQuota uncapped = PlanQuota(
        maxProjects: 1,
        maxWords: 10000,
        maxExportsPerMonth: 50,
        maxStorageBytes: 100,
        maxSeats: 1,
        dailyAiRewrites: 2,
        monthlyAiCovers: 0,
      );

      expect(capped, isNot(uncapped));
      expect(capped.hashCode, isNot(uncapped.hashCode));
    });
  });

  group('the token allowance of the plans', () {
    test('the free plan sells no token and caps none', () {
      expect(PlanDefinition.free.quota.monthlyAiTokens, 0);
    });

    test('the writer plan sells 500 k tokens per month', () {
      expect(PlanDefinition.writer.quota.monthlyAiTokens, 500000);
    });

    test('the pro plan sells 2 M tokens per month', () {
      expect(PlanDefinition.pro.quota.monthlyAiTokens, 2000000);
    });

    test('the studio plan keeps the allowance of the pro plan', () {
      expect(PlanDefinition.studio.quota.monthlyAiTokens, 2000000);
      expect(PlanDefinition.studioYearly.quota.monthlyAiTokens, 2000000);
    });

    test('the four plans declare their allowance', () {
      final Map<SubscriptionPlan, int> expected = <SubscriptionPlan, int>{
        SubscriptionPlan.free: 0,
        SubscriptionPlan.writer: 500000,
        SubscriptionPlan.pro: 2000000,
        SubscriptionPlan.studio: 2000000,
      };

      for (final SubscriptionPlan plan in SubscriptionPlan.values) {
        expect(
          PlanDefinition.of(plan).quota.monthlyAiTokens,
          expected[plan],
          reason: 'the allowance of the ${plan.name} plan',
        );
      }
    });
  });
}
