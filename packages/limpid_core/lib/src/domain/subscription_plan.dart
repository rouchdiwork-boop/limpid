/// The billing period of a subscription.
enum BillingPeriod {
  /// Renewed every month.
  monthly,

  /// Renewed every year.
  yearly,
}

/// The commercial plans offered by Limpid (D-15).
enum SubscriptionPlan {
  /// Free tier: one project, 10 000 words, limited AI.
  free,

  /// Writer tier: ten projects, 200 000 words, standard AI.
  writer,

  /// Pro tier: unlimited projects, premium AI, print-ready exports.
  pro,

  /// Studio tier: five seats, roles, local AI, API and webhooks.
  studio,
}

/// The quotas attached to a plan.
final class PlanQuota {
  /// Creates a quota description.
  ///
  /// [monthlyAiTokens] defaults to zero: a quota description built before
  /// the tokens were sold does not cap them.
  const PlanQuota({
    required this.maxProjects,
    required this.maxWords,
    required this.maxExportsPerMonth,
    required this.maxStorageBytes,
    required this.maxSeats,
    required this.dailyAiRewrites,
    required this.monthlyAiCovers,
    this.monthlyAiTokens = 0,
  });

  /// Maximum number of projects.
  final int maxProjects;

  /// Maximum number of words across the account.
  final int maxWords;

  /// Maximum number of exports per month.
  final int maxExportsPerMonth;

  /// Maximum storage in bytes.
  final int maxStorageBytes;

  /// Maximum number of seats.
  final int maxSeats;

  /// Number of inline AI rewrites allowed per day.
  final int dailyAiRewrites;

  /// Number of AI covers allowed per month.
  final int monthlyAiCovers;

  /// Maximum number of AI tokens allowed per month.
  ///
  /// Zero means the plan does not cap the tokens: it does not sell a token
  /// allowance, and its AI usage stays bounded by the other counters.
  final int monthlyAiTokens;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanQuota &&
          other.maxProjects == maxProjects &&
          other.maxWords == maxWords &&
          other.maxExportsPerMonth == maxExportsPerMonth &&
          other.maxStorageBytes == maxStorageBytes &&
          other.maxSeats == maxSeats &&
          other.dailyAiRewrites == dailyAiRewrites &&
          other.monthlyAiCovers == monthlyAiCovers &&
          other.monthlyAiTokens == monthlyAiTokens);

  @override
  int get hashCode => Object.hash(
    PlanQuota,
    maxProjects,
    maxWords,
    maxExportsPerMonth,
    maxStorageBytes,
    maxSeats,
    dailyAiRewrites,
    monthlyAiCovers,
    monthlyAiTokens,
  );
}

/// The commercial description of a plan.
final class PlanDefinition {
  /// Creates a plan definition.
  const PlanDefinition({
    required this.plan,
    required this.displayName,
    required this.priceInCents,
    required this.quota,
    this.period = BillingPeriod.monthly,
    this.isUnlimitedProjects = false,
    this.isUnlimitedExports = false,
    this.hasRag = false,
    this.hasLocalAi = false,
    this.hasApiAccess = false,
    this.hasPrintReadyExport = false,
  });

  /// The plan itself.
  final SubscriptionPlan plan;

  /// Name displayed in the interface.
  final String displayName;

  /// Price in euros cents for one [period].
  final int priceInCents;

  /// Billing period.
  final BillingPeriod period;

  /// Quotas of the plan.
  final PlanQuota quota;

  /// Whether the plan allows an unlimited number of projects.
  final bool isUnlimitedProjects;

  /// Whether the plan allows an unlimited number of exports.
  final bool isUnlimitedExports;

  /// Whether the plan unlocks the RAG feature.
  final bool hasRag;

  /// Whether the plan unlocks the local AI mode.
  final bool hasLocalAi;

  /// Whether the plan unlocks the public API and webhooks.
  final bool hasApiAccess;

  /// Whether the plan unlocks print-ready exports.
  final bool hasPrintReadyExport;

  /// Whether [wordCount] fits in the word quota of this plan.
  bool allowsWordCount(int wordCount) => wordCount <= quota.maxWords;

  /// Whether [projectCount] fits in the project quota of this plan.
  bool allowsProjectCount(int projectCount) =>
      isUnlimitedProjects || projectCount <= quota.maxProjects;

  /// The free plan definition.
  ///
  /// The pricing page announces no token allowance for the free tier: the
  /// plan does not sell tokens, so it does not cap them. Its AI stays
  /// bounded by the two rewrites a day and by the per-request guard.
  static const PlanDefinition free = PlanDefinition(
    plan: SubscriptionPlan.free,
    displayName: 'Gratuit',
    priceInCents: 0,
    quota: PlanQuota(
      maxProjects: 1,
      maxWords: 10000,
      maxExportsPerMonth: 50,
      maxStorageBytes: 100 * 1024 * 1024,
      maxSeats: 1,
      dailyAiRewrites: 2,
      monthlyAiCovers: 0,
    ),
  );

  /// The writer plan definition.
  ///
  /// The pricing page sells "standard AI, 500 k tokens per month".
  static const PlanDefinition writer = PlanDefinition(
    plan: SubscriptionPlan.writer,
    displayName: 'Écrivain',
    priceInCents: 999,
    quota: PlanQuota(
      maxProjects: 10,
      maxWords: 200000,
      maxExportsPerMonth: 100000,
      maxStorageBytes: 500 * 1024 * 1024,
      maxSeats: 1,
      dailyAiRewrites: 100,
      monthlyAiCovers: 5,
      monthlyAiTokens: 500000,
    ),
    isUnlimitedExports: true,
  );

  /// The pro plan definition.
  ///
  /// The pricing page sells "premium AI, 2 M tokens per month".
  static const PlanDefinition pro = PlanDefinition(
    plan: SubscriptionPlan.pro,
    displayName: 'Pro',
    priceInCents: 2499,
    quota: PlanQuota(
      maxProjects: 100000,
      maxWords: 10000000,
      maxExportsPerMonth: 100000,
      maxStorageBytes: 1024 * 1024 * 1024,
      maxSeats: 1,
      dailyAiRewrites: 1000,
      monthlyAiCovers: 50,
      monthlyAiTokens: 2000000,
    ),
    isUnlimitedProjects: true,
    isUnlimitedExports: true,
    hasRag: true,
    hasPrintReadyExport: true,
  );

  /// The studio plan definition.
  ///
  /// The pricing page sells "everything the Pro plan has": the token
  /// allowance of the Studio plan is the one of the Pro plan.
  static const PlanDefinition studio = PlanDefinition(
    plan: SubscriptionPlan.studio,
    displayName: 'Studio',
    priceInCents: 4999,
    quota: PlanQuota(
      maxProjects: 100000,
      maxWords: 10000000,
      maxExportsPerMonth: 100000,
      maxStorageBytes: 10 * 1024 * 1024 * 1024,
      maxSeats: 5,
      dailyAiRewrites: 1000,
      monthlyAiCovers: 50,
      monthlyAiTokens: 2000000,
    ),
    isUnlimitedProjects: true,
    isUnlimitedExports: true,
    hasRag: true,
    hasLocalAi: true,
    hasApiAccess: true,
    hasPrintReadyExport: true,
  );

  /// The studio plan billed yearly.
  ///
  /// The tokens are counted by month whatever the billing cycle is: the
  /// yearly plan keeps the monthly allowance of the Studio plan.
  static const PlanDefinition studioYearly = PlanDefinition(
    plan: SubscriptionPlan.studio,
    displayName: 'Studio (annuel)',
    priceInCents: 49900,
    period: BillingPeriod.yearly,
    quota: PlanQuota(
      maxProjects: 100000,
      maxWords: 10000000,
      maxExportsPerMonth: 100000,
      maxStorageBytes: 10 * 1024 * 1024 * 1024,
      maxSeats: 5,
      dailyAiRewrites: 1000,
      monthlyAiCovers: 50,
      monthlyAiTokens: 2000000,
    ),
    isUnlimitedProjects: true,
    isUnlimitedExports: true,
    hasRag: true,
    hasLocalAi: true,
    hasApiAccess: true,
    hasPrintReadyExport: true,
  );

  /// All plan definitions, monthly billing.
  static const List<PlanDefinition> all = <PlanDefinition>[
    free,
    writer,
    pro,
    studio,
  ];

  /// Returns the definition of [plan] with a monthly billing.
  static PlanDefinition of(SubscriptionPlan plan) => switch (plan) {
    SubscriptionPlan.free => free,
    SubscriptionPlan.writer => writer,
    SubscriptionPlan.pro => pro,
    SubscriptionPlan.studio => studio,
  };
}
