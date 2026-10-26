/// Les actions qui vont au serveur.
///
/// Une action distante peut être refusée par le serveur : la preuve du
/// second facteur a expiré, et l'appel repart avec `401`. L'application
/// répond à ce refus en demandant un code à l'auteur, puis en répétant
/// l'action — c'est le rôle de `runWithTwoFactor`.
///
/// Les écrans qui ont un `BuildContext` appellent `runWithTwoFactor`
/// directement. Les contrôleurs, qui n'en ont pas, reçoivent un
/// **coureur** : une fonction qui fait tourner l'action et ouvre la fenêtre
/// du code quand le serveur refuse la preuve.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/features/security/two_factor_challenge.dart';

/// La fonction qui fait tourner une action distante.
///
/// Le coureur fait tourner l'action ; quand le serveur refuse la preuve du
/// second facteur, il demande un code à l'auteur et **répète** l'action.
///
/// L'action doit donc être **répétable** : une action qui crée quelque
/// chose ne doit pas le créer deux fois.
typedef RemoteRunner = Future<T> Function<T>(Future<T> Function() action);

/// Le coureur de l'interface.
///
/// Il fait tourner l'action et ouvre la fenêtre du second facteur quand le
/// serveur refuse la preuve : l'action est alors répétée avec la preuve
/// neuve.
RemoteRunner remoteRunnerOf(BuildContext context, WidgetRef ref) {
  return <T>(Future<T> Function() action) =>
      runWithTwoFactor(context, ref, action: action);
}
