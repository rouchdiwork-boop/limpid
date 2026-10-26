/// Les routes de la publication Amazon KDP.
///
/// Les chemins vivent avec la fonctionnalité qui les possède : le routeur de
/// l'application ne fait que les déclarer.
abstract final class KdpRoutes {
  /// L'écran des dépôts du compte.
  ///
  /// C'est l'adresse que l'auteur ouvre : elle montre les dépôts qu'il a
  /// préparés et le bouton qui en prépare un nouveau.
  static const String screen = '/bibliotheque/kdp';

  /// Le motif de la route d'un dépôt.
  ///
  /// Le dépôt se lit sur sa propre adresse : l'auteur revient sur le dépôt
  /// qu'il a préparé sans repasser par la liste.
  static const String submissionPattern = '$screen/:submissionId';

  /// La route d'un dépôt.
  static String submission(String submissionId) =>
      '$screen/${Uri.encodeComponent(submissionId)}';
}
