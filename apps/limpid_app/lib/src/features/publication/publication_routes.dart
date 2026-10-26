/// The routes of the public pages of the books.
///
/// The paths live with the feature that owns them: the router of the
/// application only declares them. The two pages are **outside** the shell of
/// the application — a public page has no rail and no panel, it is a page a
/// reader opens, not a page an author works in.
abstract final class PublicationRoutes {
  /// The prefix of the public pages of a book.
  ///
  /// The prefix and the pattern are built from the same constant: the router
  /// has to recognise a public page **without** knowing its parameter, and a
  /// prefix written twice would drift from the pattern the day one of them
  /// changes.
  static const String showcasePrefix = '/vitrine/';

  /// The prefix of the reading pages of a book.
  static const String readerPrefix = '/lire/';

  /// Le préfixe des pages publiques d'un auteur.
  ///
  /// Le préfixe et le motif sont bâtis depuis la même constante, comme ceux
  /// d'un livre : le routeur doit reconnaître la page d'un auteur **sans**
  /// connaître son paramètre.
  static const String authorPrefix = '/auteur/';

  /// Le préfixe de la page de vente d'un livre.
  ///
  /// La page de vente est **publique** comme la vitrine : un lecteur la
  /// regarde sans compte, et se connecte pour acheter. Le préfixe et le
  /// motif sont bâtis depuis la même constante, comme les autres pages
  /// publiques.
  static const String salePrefix = '/vente/';

  /// Le préfixe de l'écran de retour du paiement d'un livre.
  ///
  /// L'écran de retour est **public** : c'est le prestataire de paiement qui
  /// y renvoie l'acheteur, et l'acheteur peut ne pas être connecté quand il
  /// arrive.
  static const String paymentReturnPrefix = '/retour-paiement/';

  /// The pattern of the public page of a book.
  static const String showcasePattern = '$showcasePrefix:projectId';

  /// The pattern of the reading page of a book.
  static const String readerPattern = '$readerPrefix:projectId';

  /// Le motif de la page publique d'un auteur.
  static const String authorPattern = '$authorPrefix:authorId';

  /// Le motif de la page de vente d'un livre.
  static const String salePattern = '$salePrefix:projectId';

  /// Le motif de l'écran de retour du paiement d'un livre.
  static const String paymentReturnPattern = '$paymentReturnPrefix:projectId';

  /// The public page of the given book.
  static String showcase(String projectId) => '$showcasePrefix$projectId';

  /// The reading page of the given book.
  static String reader(String projectId) => '$readerPrefix$projectId';

  /// La page publique de l'auteur donné.
  static String author(String authorId) => '$authorPrefix$authorId';

  /// La page de vente du livre donné.
  static String sale(String projectId) => '$salePrefix$projectId';

  /// L'écran de retour du paiement du livre donné.
  static String paymentReturn(String projectId) =>
      '$paymentReturnPrefix$projectId';
}
