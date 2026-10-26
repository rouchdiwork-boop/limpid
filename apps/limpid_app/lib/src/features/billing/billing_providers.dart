import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/billing/billing_routes.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';
import 'package:limpid_core/limpid_core.dart';

/// Le cycle de facturation que l'auteur regarde.
///
/// Le choix vit dans l'écran : il ne change ni la formule du compte ni son
/// cycle réel, il ne change que le prix affiché.
final billingPeriodProvider =
    NotifierProvider<BillingPeriodNotifier, BillingPeriod>(
      BillingPeriodNotifier.new,
    );

/// Le cycle affiché par l'écran de formule.
final class BillingPeriodNotifier extends Notifier<BillingPeriod> {
  @override
  BillingPeriod build() => BillingPeriod.monthly;

  /// Affiche le cycle [period].
  void select(BillingPeriod period) {
    if (period == state) return;
    state = period;
  }
}

/// L'abonnement du compte, lu sur le serveur.
final accountPlanProvider = FutureProvider<AccountPlan>((Ref ref) async {
  return runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(planRepositoryProvider).currentPlan(),
  );
});

/// Le catalogue des formules, lu sur le serveur.
final planOffersProvider = FutureProvider<List<PlanOffer>>((Ref ref) async {
  return runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(planRepositoryProvider).offers(),
  );
});

/// La consommation du cycle en cours, lue sur le serveur.
final quotaUsageProvider = FutureProvider<List<QuotaReading>>((Ref ref) async {
  return runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(planRepositoryProvider).usage(),
  );
});

/// L'état de l'ouverture d'une session de paiement.
@immutable
class CheckoutState {
  /// Crée un état.
  const CheckoutState({this.isRunning = false, this.session});

  /// Indique si une session est en cours d'ouverture.
  final bool isRunning;

  /// La session ouverte, `null` quand aucune session ne l'a été.
  final CheckoutSession? session;
}

/// Ouvre les sessions de paiement et change la formule du compte.
///
/// L'état porte la session ouverte : l'écran l'affiche à l'auteur, qui la
/// suit pour payer. Un échec remonte à l'appelant — l'écran montre alors le
/// message du serveur, ou celui du service absent.
final checkoutProvider = NotifierProvider<CheckoutNotifier, CheckoutState>(
  CheckoutNotifier.new,
);

/// Le contrôleur des paiements de l'écran de formule.
final class CheckoutNotifier extends Notifier<CheckoutState> {
  @override
  CheckoutState build() => const CheckoutState();

  /// Ouvre une session de paiement pour la formule [plan].
  ///
  /// Une seule session s'ouvre à la fois : une seconde demande pendant que
  /// la première court est refusée, le serveur n'accepte pas deux sessions
  /// pour le même compte.
  Future<CheckoutSession> open({
    required SubscriptionPlan plan,
    required BillingPeriod period,
  }) async {
    if (state.isRunning) {
      throw StateError('A checkout session is already being opened.');
    }
    state = const CheckoutState(isRunning: true);
    try {
      final CheckoutSession session = await ref
          .read(planRepositoryProvider)
          .openCheckout(
            plan: plan,
            period: period,
            returnTo: Uri.parse(BillingRoutes.subscription),
          );
      state = CheckoutState(isRunning: false, session: session);
      return session;
    } on Object {
      state = const CheckoutState();
      rethrow;
    }
  }

  /// Change la formule du compte, sans paiement.
  ///
  /// La formule gratuite ne se paie pas : elle se change directement. Le
  /// serveur trace le changement dans son journal d'audit.
  Future<AccountPlan> change({
    required SubscriptionPlan plan,
    required BillingPeriod period,
  }) async {
    final AccountPlan changed = await ref
        .read(planRepositoryProvider)
        .changePlan(plan: plan, period: period);
    ref.invalidate(accountPlanProvider);
    return changed;
  }
}
