/// Les routes de l'écran du back-office.
///
/// Les chemins vivent avec la fonctionnalité qui les possède : le routeur de
/// l'application ne fait que les déclarer.
abstract final class AdminRoutes {
  /// Le segment du back-office, relatif aux réglages.
  ///
  /// Le routeur de l'application déclare ce segment : le chemin complet
  /// n'est bâti qu'une fois, ici.
  static const String segment = 'back-office';

  /// La page du back-office.
  ///
  /// La page vit avec les réglages : elle montre les comptes du service et
  /// les indicateurs de fonctionnalité, elle ne fait pas partie du travail
  /// d'écriture de l'auteur.
  static const String list = '/reglages/$segment';

  /// Le motif de la page d'un compte.
  ///
  /// Le motif est bâti depuis la même constante que le chemin : le routeur
  /// doit reconnaître la page d'un compte **sans** connaître son paramètre.
  static const String accountPattern = '$list/$accountSegment/:userId';

  /// Le segment d'un compte, relatif au back-office.
  static const String accountSegment = 'comptes';

  /// La page du compte [userId].
  static String account(String userId) =>
      '$list/$accountSegment/${Uri.encodeComponent(userId)}';
}
