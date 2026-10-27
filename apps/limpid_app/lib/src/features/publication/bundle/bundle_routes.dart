/// Les routes des pages du bundle.
///
/// Les chemins vivent avec la feature qui les possède : le routeur de
/// l'application ne fait que les déclarer. Les pages du bundle sont
/// **publiques** comme la vitrine : un lecteur les regarde sans compte, et
/// se connecte pour acheter.
abstract final class BundleRoutes {
  /// Le préfixe de la page d'un bundle.
  ///
  /// Le préfixe et le motif sont bâtis depuis la même constante, comme ceux
  /// des pages publiques d'un livre : le routeur doit reconnaître la page
  /// d'un bundle **sans** connaître son paramètre.
  static const String bundlePrefix = '/bundle/';

  /// Le préfixe de l'écran de retour du paiement d'un bundle.
  ///
  /// L'écran de retour est **public** : c'est le prestataire de paiement
  /// qui y renvoie l'acheteur, et l'acheteur peut ne pas être connecté
  /// quand il arrive.
  static const String paymentReturnPrefix = '/retour-paiement-bundle/';

  /// Le motif de la page d'un bundle.
  static const String bundlePattern = '$bundlePrefix:bundleId';

  /// Le motif de l'écran de retour du paiement d'un bundle.
  static const String paymentReturnPattern = '$paymentReturnPrefix:bundleId';

  /// La page du bundle donné.
  static String bundle(String bundleId) => '$bundlePrefix$bundleId';

  /// L'écran de retour du paiement du bundle donné.
  static String paymentReturn(String bundleId) =>
      '$paymentReturnPrefix$bundleId';
}
