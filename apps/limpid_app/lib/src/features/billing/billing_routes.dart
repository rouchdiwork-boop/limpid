/// Les routes de l'écran de formule et de facturation.
///
/// Le chemin vit avec la fonctionnalité qui le possède : le routeur de
/// l'application ne fait que le déclarer.
abstract final class BillingRoutes {
  /// L'écran de l'abonnement.
  ///
  /// C'est aussi l'adresse où le paiement renvoie l'auteur : le service de
  /// paiement la reçoit et l'utilise comme URL de retour.
  static const String subscription = '/abonnement';
}
