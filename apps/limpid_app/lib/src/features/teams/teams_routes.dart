/// Les routes de l'écran des équipes.
///
/// Les chemins vivent avec la fonctionnalité qui les possède : le routeur de
/// l'application ne fait que les déclarer.
abstract final class TeamsRoutes {
  /// Le segment des équipes, relatif à la bibliothèque.
  ///
  /// Le routeur de l'application déclare ce segment : le chemin complet
  /// n'est bâti qu'une fois, ici.
  static const String segment = 'equipes';

  /// La liste des équipes du compte.
  ///
  /// L'écran vit dans la bibliothèque : les équipes écrivent les livres
  /// de l'auteur, au même endroit que la distribution chez Amazon.
  static const String list = '/bibliotheque/$segment';

  /// Le motif de la page d'une équipe.
  ///
  /// Le motif est bâti depuis la même constante que le chemin : le routeur
  /// doit reconnaître la page d'une équipe **sans** connaître son paramètre.
  static const String detailPattern = '$list/:teamId';

  /// La page de l'équipe [teamId].
  static String detail(String teamId) => '$list/${Uri.encodeComponent(teamId)}';
}
