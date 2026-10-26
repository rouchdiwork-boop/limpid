/// L'ouverture de l'adresse de paiement d'une commande.
///
/// L'adresse vient du serveur : elle est signée et elle expire. L'ouvrir
/// est une opération de la plateforme, pas de l'écran : le port la décrit,
/// et la plateforme la réalise.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'payment_opener_io.dart'
    if (dart.library.js_interop) 'payment_opener_web.dart';

/// Le port qui ouvre l'adresse de paiement d'une commande.
///
/// Renvoie `false` quand la plateforme ne sait pas l'ouvrir : l'écran le
/// dit alors, plutôt que de faire semblant que le paiement a commencé.
abstract interface class PaymentOpener {
  /// Ouvre l'adresse [url] du prestataire de paiement.
  ///
  /// Renvoie `false` quand l'adresse n'a pas pu être ouverte, ou quand la
  /// plateforme ne le permet pas.
  Future<bool> open(Uri url);
}

/// L'ouverture du paiement, par la plateforme de l'application.
///
/// Sur le web, l'adresse s'ouvre dans le **même onglet** : le prestataire de
/// paiement ne rend pas dans une fenêtre, et un second onglet laisserait
/// l'acheteur devant une page vide. Sur les plateformes natives,
/// l'application ne peut pas ouvrir une page de paiement : elle le dit.
final paymentOpenerProvider = Provider<PaymentOpener>((Ref ref) {
  return const PlatformPaymentOpener();
});

/// L'ouverture du paiement par la plateforme de l'application.
final class PlatformPaymentOpener implements PaymentOpener {
  /// Crée l'ouverture.
  const PlatformPaymentOpener();

  @override
  Future<bool> open(Uri url) => openPaymentAddress(url);
}
