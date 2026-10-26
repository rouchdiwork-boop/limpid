import 'package:limpid_app/src/domain/admin_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_core/limpid_core.dart';

/// Le compte que la doublure sert.
final AdminAccount fakeAccount = AdminAccount(
  userId: 'auteur-1',
  email: 'auteur@exemple.fr',
  plan: 'studio',
  projectCount: 3,
  collaborationCount: 2,
  commentCount: 5,
  operationCount: 12,
  lastActivityAt: DateTime.utc(2026, 10, 20, 8),
  isPurged: false,
);

/// Un second compte, dont les données ont été effacées.
const AdminAccount fakePurgedAccount = AdminAccount(
  userId: 'auteur-2',
  email: null,
  plan: null,
  projectCount: 0,
  collaborationCount: 0,
  commentCount: 0,
  operationCount: 0,
  lastActivityAt: null,
  isPurged: true,
);

/// L'indicateur que la doublure sert.
final AdminFeatureFlag fakeFlag = AdminFeatureFlag(
  key: 'ai_premium',
  isEnabled: false,
  description: "L'assistant premium répond à toutes les demandes.",
  updatedAt: DateTime.utc(2026, 10, 20, 8),
  updatedBy: 'admin-1',
);

/// Un second indicateur, déjà actif.
final AdminFeatureFlag fakeEnabledFlag = AdminFeatureFlag(
  key: 'kdp_publish',
  isEnabled: true,
  description: 'Les dépôts chez Amazon KDP sont ouverts.',
  updatedAt: DateTime.utc(2026, 10, 21, 9),
  updatedBy: 'admin-1',
);

/// Le dépôt du back-office, tenu en mémoire.
///
/// La doublure sert les comptes et les indicateurs qu'on lui donne, et
/// note les changements d'indicateurs : le test pilote l'écran, elle ne lit
/// rien du serveur.
final class FakeAdminRepository implements AdminRepository {
  /// Crée un dépôt.
  FakeAdminRepository({
    List<AdminAccount>? accounts,
    List<AdminFeatureFlag>? flags,
  }) : accountList = <AdminAccount>[...?accounts],
       flagList = <AdminFeatureFlag>[...?flags];

  /// Les comptes que le dépôt sert.
  final List<AdminAccount> accountList;

  /// Les indicateurs que le dépôt sert.
  final List<AdminFeatureFlag> flagList;

  /// L'erreur que chaque lecture lève quand elle est posée.
  Object? error;

  /// L'erreur que l'activation d'un indicateur lève quand elle est posée.
  Object? changeError;

  /// Les changements d'indicateurs demandés par l'écran.
  final List<(String, bool)> changes = <(String, bool)>[];

  @override
  Future<List<AdminAccount>> accounts() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<AdminAccount>.unmodifiable(accountList);
  }

  @override
  Future<AdminAccount> account(String userId) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    for (final AdminAccount account in accountList) {
      if (account.userId == userId) return account;
    }
    throw const ApiNotFoundException("Ce compte n'existe pas.");
  }

  @override
  Future<List<AdminFeatureFlag>> featureFlags() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<AdminFeatureFlag>.unmodifiable(flagList);
  }

  @override
  Future<AdminFeatureFlag> setFeatureFlag(
    String key, {
    required bool isEnabled,
  }) async {
    final Object? failure = changeError ?? error;
    if (failure != null) throw failure;
    changes.add((key, isEnabled));
    final AdminFeatureFlag changed = fakeFlag.copyWith(
      isEnabled: isEnabled,
      updatedAt: DateTime.utc(2026, 10, 26, 10),
    );
    final int index = flagList.indexWhere(
      (AdminFeatureFlag flag) => flag.key == key,
    );
    if (index < 0) {
      flagList.add(changed);
    } else {
      flagList[index] = changed;
    }
    return changed;
  }
}

/// Le catalogue des formules que la doublure sert.
///
/// Le back-office ne lit que le catalogue : le reste du port de la formule
/// n'est pas câblé, et la doublure le dit.
final class FakePlanRepository implements PlanRepository {
  /// Crée un catalogue.
  FakePlanRepository({List<PlanOffer>? offers})
    : planOffers = <PlanOffer>[...?offers];

  /// Les formules du catalogue.
  final List<PlanOffer> planOffers;

  @override
  Future<List<PlanOffer>> offers() async =>
      List<PlanOffer>.unmodifiable(planOffers);

  @override
  Future<AccountPlan> currentPlan() async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<QuotaReading>> usage() async =>
      throw const ServiceUnavailableException();

  @override
  Future<AccountPlan> changePlan({
    required SubscriptionPlan plan,
    required BillingPeriod period,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<CheckoutSession> openCheckout({
    required SubscriptionPlan plan,
    required BillingPeriod period,
    required Uri returnTo,
  }) async => throw const ServiceUnavailableException();
}
