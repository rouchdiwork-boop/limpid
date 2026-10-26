/// Les lectures du back-office.
///
/// Les écrans lisent ces états : la liste des comptes, le détail d'un compte
/// et les indicateurs de fonctionnalité. Aucun écran n'atteint le serveur
/// lui-même.
///
/// Les lectures passent par la fenêtre du second facteur : le serveur
/// réserve le back-office à l'administrateur, et il peut demander la preuve
/// du second facteur avant d'y répondre.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/admin_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/plan_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';

/// Les comptes du service, lus sur le serveur.
final adminAccountsProvider = FutureProvider<List<AdminAccount>>((Ref ref) {
  return _reading(
    () => runWithTwoFactorGlobally(
      ref,
      action: () => ref.watch(adminRepositoryProvider).accounts(),
    ),
  );
});

/// Le compte [userId], lu sur le serveur.
final adminAccountProvider = FutureProvider.family<AdminAccount, String>((
  Ref ref,
  String userId,
) {
  return _reading(
    () => runWithTwoFactorGlobally(
      ref,
      action: () => ref.watch(adminRepositoryProvider).account(userId),
    ),
  );
});

/// Les indicateurs de fonctionnalité, lus sur le serveur.
final adminFeatureFlagsProvider = FutureProvider<List<AdminFeatureFlag>>((
  Ref ref,
) {
  return _reading(
    () => runWithTwoFactorGlobally(
      ref,
      action: () => ref.watch(adminRepositoryProvider).featureFlags(),
    ),
  );
});

/// La lecture d'une ressource du back-office.
///
/// Les erreurs de l'API gardent leur type : l'écran distingue le refus de
/// l'administrateur d'une panne. Les autres exceptions disent que le
/// service n'est pas disponible — le port n'est pas câblé, et Riverpod
/// enveloppe alors son refus dans une exception qui n'est plus une erreur de
/// l'API.
Future<T> _reading<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on ApiException {
    rethrow;
  } on ServiceUnavailableException {
    rethrow;
  } on Exception {
    throw const ServiceUnavailableException();
  }
}

/// Les sièges de chaque formule du catalogue.
///
/// Le catalogue est un autre port : son échec ne doit pas cacher le compte.
/// L'écran montre alors les compteurs du compte, sans le nombre de sièges —
/// jamais un chiffre qu'il n'a pas lu.
final adminPlanSeatsProvider = FutureProvider<Map<String, int>>((
  Ref ref,
) async {
  try {
    final List<PlanOffer> offers = await ref
        .watch(planRepositoryProvider)
        .offers();
    return Map<String, int>.unmodifiable(<String, int>{
      for (final PlanOffer offer in offers) offer.plan.name: offer.seatCount,
    });
  } on Object catch (error) {
    debugPrint(
      'Le catalogue des formules ne dit pas les sièges des formules ($error).',
    );
    return const <String, int>{};
  }
});
