/// Les chemins de l'écran des livres achetés.
///
/// L'écran vit dans l'espace du compte : il accompagne la bibliothèque, où
/// l'auteur trouve déjà les pages de ses livres. Les chemins sont bâtis
/// depuis la même constante, comme ceux des autres pages.
abstract final class PurchasesRoutes {
  /// Le chemin de l'écran des livres achetés.
  static const String purchases = '/bibliotheque/achats';

  /// Le segment de l'écran, relatif à la bibliothèque.
  static const String segment = 'achats';
}
