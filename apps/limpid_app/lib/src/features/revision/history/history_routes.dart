/// Les routes de l'historique des versions.
///
/// Les chemins vivent avec la fonctionnalité qui les possède : le routeur de
/// l'application ne fait que les déclarer.
abstract final class HistoryRoutes {
  /// Le segment de l'historique, relatif au document.
  ///
  /// Le routeur de l'application déclare ce segment : le chemin complet
  /// n'est bâti qu'une fois, ici.
  static const String segment = 'historique';

  /// Le motif de la page de l'historique d'un document.
  ///
  /// Le motif est bâti depuis la même constante que le chemin : le routeur
  /// doit reconnaître la page **sans** connaître son paramètre.
  static const String detailPattern = '/documents/:documentId/$segment';

  /// La page de l'historique du document [documentId].
  static String detail(String documentId) =>
      '/documents/${Uri.encodeComponent(documentId)}/$segment';
}
