import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/auth/two_factor_proof_holder.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';
import 'package:limpid_app/src/features/security/two_factor_dialogs.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// Pourquoi le serveur a refusé la requête.
enum TwoFactorRefusal {
  /// Le second facteur est en cause : la preuve est absente, expirée ou
  /// refusée. L'application demande un code à l'auteur.
  secondFactor,

  /// La session de l'auteur n'est plus valable. L'application rend l'erreur
  /// telle quelle : demander un code ne la réparerait pas.
  session,

  /// La formule du compte exige la double authentification et le compte ne
  /// l'a pas activée. L'application invite l'auteur à l'activer.
  required,
}

/// Classe un refus du serveur.
///
/// La décision ne lit **jamais** le message du serveur : elle regarde l'état
/// du client, c'est-à-dire la preuve que l'application porte et l'état du
/// compte.
///
/// - Une preuve que l'application porte et qui n'est pas expirée : le
///   serveur a refusé une preuve qu'il devait accepter — le refus porte sur
///   le second facteur.
/// - Une preuve expirée ne vaut plus rien : elle est écartée, et l'état du
///   compte décide.
/// - Sans preuve, l'état du compte décide : un compte dont le second
///   facteur est actif doit en fournir une, un compte qui ne l'a pas activé
///   a simplement une session invalide.
Future<TwoFactorRefusal> classifyRefusal({
  required TwoFactorRepository repository,
  required TwoFactorProof? proof,
  int? statusCode,
  DateTime? now,
}) async {
  final DateTime moment = now ?? DateTime.now().toUtc();
  final TwoFactorStatus? status = await _statusOf(repository);

  // Le serveur ne répond 403 que lorsque la formule exige le second
  // facteur : l'état du compte le confirme.
  if (statusCode == 403 && status != null && status.needsActivation) {
    return TwoFactorRefusal.required;
  }

  if (proof != null && !proof.isExpiredAt(moment)) {
    return TwoFactorRefusal.secondFactor;
  }

  if (status != null && status.enabled) {
    return TwoFactorRefusal.secondFactor;
  }

  return TwoFactorRefusal.session;
}

/// Exécute [action] et, quand le refus vient du second facteur, demande un
/// code à l'auteur et **répète** l'action.
///
/// Cette forme est celle des **lectures** : elles vivent dans des
/// `FutureProvider`, qui n'ont pas de `BuildContext`. La clé de navigation
/// de la composition racine fournit le contexte qui ouvre la fenêtre.
///
/// Sans interface — avant le premier cadre, ou dans un test — l'action est
/// exécutée telle quelle : il n'y a personne à qui demander un code.
Future<T> runWithTwoFactorGlobally<T>(
  Ref ref, {
  required Future<T> Function() action,
}) {
  final BuildContext? context = ref.read(navigatorKeyProvider).currentContext;
  return _runWithTwoFactor(
    context,
    () => ref.read(twoFactorRepositoryProvider),
    action: action,
  );
}

/// Exécute [action] et, quand le refus vient du second facteur, demande un
/// code à l'auteur et **répète** l'action.
///
/// L'action est répétée une seule fois : une seconde preuve refusée laisse
/// remonter l'erreur du serveur, l'application ne boucle pas sur une
/// fenêtre de code.
Future<T> runWithTwoFactor<T>(
  BuildContext context,
  WidgetRef ref, {
  required Future<T> Function() action,
}) => _runWithTwoFactor(
  context,
  () => ref.read(twoFactorRepositoryProvider),
  action: action,
);

/// Le coeur de la tentative, partage par les ecrans et par les lectures.
///
/// [read] lit un port : les ecrans ont un `WidgetRef`, les lectures un
/// `Ref`, et les deux savent lire. [context] peut etre `null` : sans
/// interface, il n'y a personne a qui demander un code, et l'erreur
/// remonte telle quelle.
Future<T> _runWithTwoFactor<T>(
  BuildContext? context,
  TwoFactorRepository Function() repository, {
  required Future<T> Function() action,
}) async {
  try {
    return await action();
  } on ApiUnauthorizedException catch (error) {
    final TwoFactorProof? proof = TwoFactorProofHolder.current;
    final TwoFactorRefusal refusal = await classifyRefusal(
      repository: repository(),
      proof: proof,
      statusCode: error.statusCode,
    );

    if (refusal == TwoFactorRefusal.required) {
      if (context != null && context.mounted) {
        LimpidSnackbar.show(
          context,
          message: AppLocalizations.of(context).twoFactorRequired,
          variant: LimpidStatusVariant.warning,
        );
      }
      rethrow;
    }

    if (refusal != TwoFactorRefusal.secondFactor) {
      rethrow;
    }

    // La preuve que l'application portait ne vaut plus rien : elle est
    // oubliée avant d'en demander une autre.
    TwoFactorProofHolder.clear();

    if (context == null || !context.mounted) {
      rethrow;
    }

    final TwoFactorProof? accepted = await showTwoFactorCodeDialog(context);
    if (accepted == null) {
      // L'auteur a renoncé : l'erreur du serveur remonte telle quelle.
      rethrow;
    }

    TwoFactorProofHolder.set(accepted);

    // La requête est répétée : elle part maintenant avec la preuve.
    return await action();
  }
}

/// L'état du compte, quand il est lisible.
Future<TwoFactorStatus?> _statusOf(TwoFactorRepository repository) async {
  try {
    return await repository.status();
  } on Object {
    // L'état du compte est illisible : le refus n'est pas attribuable au
    // second facteur, il est rendu tel quel.
    return null;
  }
}
