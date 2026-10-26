import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_core/limpid_core.dart';

/// The four formulas of the catalogue, with the limits of D-15.
///
/// The prices and the limits are the ones the server publishes : the test
/// n'invente pas un autre catalogue.
const List<PlanOffer> fakeOffers = <PlanOffer>[
  PlanOffer(
    plan: SubscriptionPlan.free,
    displayName: 'Gratuit',
    priceInCents: 0,
    seatCount: 1,
    maxWords: 10000,
    maxAiUsage: 2,
    maxStorageBytes: 100 * 1024 * 1024,
  ),
  PlanOffer(
    plan: SubscriptionPlan.writer,
    displayName: 'Écrivain',
    priceInCents: 999,
    trialDays: 14,
    seatCount: 1,
    maxWords: 200000,
    maxAiUsage: 100,
    maxStorageBytes: 500 * 1024 * 1024,
  ),
  PlanOffer(
    plan: SubscriptionPlan.pro,
    displayName: 'Pro',
    priceInCents: 2499,
    seatCount: 1,
    maxWords: 10000000,
    maxAiUsage: 1000,
    maxStorageBytes: 1024 * 1024 * 1024,
  ),
  PlanOffer(
    plan: SubscriptionPlan.studio,
    displayName: 'Studio',
    priceInCents: 4999,
    yearlyPriceInCents: 49900,
    seatCount: 5,
    maxWords: 10000000,
    maxAiUsage: 1000,
    maxStorageBytes: 10 * 1024 * 1024 * 1024,
  ),
];

/// The consumption of the cycle en cours.
const List<QuotaReading> fakeReadings = <QuotaReading>[
  QuotaReading(meter: QuotaMeter.words, limit: 10000000, used: 482010),
  QuotaReading(meter: QuotaMeter.aiUsage, limit: 1000, used: 341),
  QuotaReading(
    meter: QuotaMeter.storage,
    limit: 1024 * 1024 * 1024,
    used: 42 * 1024 * 1024,
  ),
];

/// The subscription of the account : the formula Pro, en abonnement actif.
final AccountPlan fakeProPlan = AccountPlan(
  plan: SubscriptionPlan.pro,
  displayName: 'Pro',
  status: PlanStatus.active,
  period: BillingPeriod.monthly,
  periodStartedAt: DateTime.utc(2026, 11, 1),
  periodEndsAt: DateTime.utc(2026, 11, 30),
  seatCount: 1,
);

/// A [PlanRepository] the test drives by hand.
///
/// The fake holds the abonnement, le catalogue et la consommation que le
/// test donne à l'écran : il ne lit rien du serveur.
final class FakePlanRepository implements PlanRepository {
  /// Creates a repository.
  FakePlanRepository({
    AccountPlan? subscription,
    List<PlanOffer>? catalogue,
    List<QuotaReading>? readings,
  }) : subscription = subscription ?? fakeProPlan,
       catalogue = catalogue ?? fakeOffers,
       readings = readings ?? fakeReadings;

  /// The subscription the repository serves.
  AccountPlan subscription;

  /// The catalogue the repository serves.
  List<PlanOffer> catalogue;

  /// The consumption the repository serves.
  List<QuotaReading> readings;

  /// The error every read throws when it is set.
  Object? error;

  /// The error the changes of formula throw when it is set.
  Object? changeError;

  /// The session the repository opens.
  CheckoutSession session = const CheckoutSession(
    id: 'cs_test_1',
    url: 'https://checkout.test/session/1',
  );

  /// The formulas the author asked for.
  final List<SubscriptionPlan> chosen = <SubscriptionPlan>[];

  /// The sessions the repository opened.
  final List<SubscriptionPlan> paid = <SubscriptionPlan>[];

  @override
  Future<AccountPlan> currentPlan() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return subscription;
  }

  @override
  Future<List<PlanOffer>> offers() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return catalogue;
  }

  @override
  Future<List<QuotaReading>> usage() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return readings;
  }

  @override
  Future<AccountPlan> changePlan({
    required SubscriptionPlan plan,
    required BillingPeriod period,
  }) async {
    final Object? failure = changeError ?? error;
    if (failure != null) throw failure;
    chosen.add(plan);
    subscription = AccountPlan(
      plan: plan,
      displayName: 'Gratuit',
      status: PlanStatus.free,
      period: period,
      periodStartedAt: DateTime.utc(2026, 11, 1),
    );
    return subscription;
  }

  @override
  Future<CheckoutSession> openCheckout({
    required SubscriptionPlan plan,
    required BillingPeriod period,
    required Uri returnTo,
  }) async {
    final Object? failure = changeError ?? error;
    if (failure != null) throw failure;
    paid.add(plan);
    return session;
  }
}
