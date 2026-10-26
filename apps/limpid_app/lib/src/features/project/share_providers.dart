/// Les partages en lecture du compte, lus sur le serveur.
///
/// L'écran d'un livre lit ces états pour montrer les liens qu'il a déjà
/// partagés ; il n'atteint jamais le serveur lui-même.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/share_repository.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';

/// Les partages en lecture du compte.
///
/// La lecture est distante : elle passe par la fenêtre du second facteur,
/// comme les autres lectures de l'application.
final accountSharesProvider = FutureProvider<List<Share>>((Ref ref) async {
  return runWithTwoFactorGlobally(
    ref,
    action: () => ref.watch(shareRepositoryProvider).shares(),
  );
});

/// Les partages du livre [projectId].
///
/// Le serveur rend tous les partages du compte ; l'écran d'un livre ne
/// montre que les siens. Tant que la liste n'est pas connue, l'écran
/// affiche les partages qu'il a : aucun.
final projectSharesProvider = Provider.family<List<Share>, String>((
  Ref ref,
  String projectId,
) {
  final List<Share>? shares = ref.watch(accountSharesProvider).value;
  if (shares == null) return const <Share>[];
  return List<Share>.unmodifiable(
    shares.where((Share share) => share.projectId == projectId),
  );
});
