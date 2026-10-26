import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/session_controller.dart';
import 'package:limpid_app/src/auth/two_factor_proof_holder.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';

/// L'état de la double authentification du compte, lu sur le serveur.
///
/// L'écran de sécurité lit cet état : il dit si le compte est inscrit, si le
/// second facteur est actif et si la formule l'exige.
final twoFactorStatusProvider = FutureProvider<TwoFactorStatus>((
  Ref ref,
) async {
  return ref.watch(twoFactorRepositoryProvider).status();
});

/// La session de l'auteur, observée pour lâcher la preuve du second facteur.
///
/// La preuve appartient à la **session** : elle n'est jamais écrite sur le
/// disque, et elle tombe quand la session se ferme. L'écran de sécurité lit
/// ce port ; le point de composition doit le lire aussi, pour que la preuve
/// tombe même quand l'auteur n'ouvre jamais l'écran de sécurité.
final twoFactorSessionProvider = Provider<AsyncValue<AuthSession?>>((Ref ref) {
  final AsyncValue<AuthSession?> session = ref.watch(sessionControllerProvider);
  // La session se ferme : la preuve ne vaut plus rien. Le port est relu à
  // chaque changement de session, l'oubli de la preuve est donc immédiat.
  if (session is AsyncData<AuthSession?> && session.value == null) {
    TwoFactorProofHolder.clear();
  }
  return session;
});
