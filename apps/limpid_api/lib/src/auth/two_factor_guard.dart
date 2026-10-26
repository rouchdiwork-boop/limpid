import 'package:shelf/shelf.dart';

import 'auth_context.dart';

/// Le contrôle du second facteur, exécuté après la vérification du jeton.
///
/// Le contrôle vit dans la couche d'authentification : la présence de la
/// preuve du second facteur est vérifiée au même endroit que la présence du
/// jeton, et aucune route n'a à s'en soucier.
///
/// L'implémentation lève une `ForbiddenException` quand la formule du
/// compte exige la double authentification sans que l'appelant l'ait
/// activée, et une `UnauthorizedException` quand la preuve du second
/// facteur est absente, invalide ou expirée.
abstract interface class TwoFactorGuard {
  /// Vérifie le second facteur de l'appelant [auth].
  ///
  /// La requête [request] porte la preuve, dans l'en-tête `x-limpid-2fa`.
  Future<void> verifySecondFactor(AuthContext auth, Request request);
}
