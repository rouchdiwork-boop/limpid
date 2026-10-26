/// L'état de la vente d'un livre.
///
/// Un livre se prépare, se publie, puis se retire. Ce sont les trois seuls
/// états : un livre qui n'est pas dans l'un d'eux n'est pas en vente, et le
/// serveur ne le vend pas.
enum BookSaleStatus {
  /// Le livre est en préparation : il n'est pas encore en vente.
  draft('draft'),

  /// Le livre est en vente.
  published('published'),

  /// Le livre a été retiré de la vente.
  withdrawn('withdrawn');

  const BookSaleStatus(this.key);

  /// Le nom technique de l'état, écrit dans la base.
  final String key;

  /// L'état nommé [raw], `null` quand il est inconnu.
  static BookSaleStatus? parse(String raw) {
    final String normalized = raw.trim().toLowerCase();
    for (final BookSaleStatus status in BookSaleStatus.values) {
      if (status.key == normalized) return status;
    }
    return null;
  }
}

/// Les devises acceptées par la vente d'un livre.
///
/// La liste est **fermée** : un livre se vend en euros. Une devise
/// supplémentaire demanderait un taux de change, donc une date de taux,
/// donc une décision qui n'appartient pas à cette étape.
const List<String> bookSaleCurrencies = <String>['eur'];

/// La vente d'un livre : son prix, sa devise et l'état de la vente.
///
/// Le prix est une donnée **du livre**, pas de la formule : un livre se
/// vend une fois, pas par mois. La ligne est unique par livre.
///
/// Les parts sont comptées en millièmes : 9 000 millièmes font 90 % pour
/// l'auteur. Elles sont configurables par compte, et la règle par défaut
/// est celle du service de partage des revenus.
final class BookSaleRecord {
  /// Crée une vente.
  const BookSaleRecord({
    required this.projectId,
    required this.ownerId,
    required this.title,
    required this.priceInCents,
    required this.currency,
    required this.status,
    required this.authorShare,
    required this.platformShare,
    required this.createdAt,
    required this.updatedAt,
    this.artifactKey,
    this.publishedAt,
  });

  /// Le livre vendu.
  final String projectId;

  /// Le compte qui possède le livre et encaisse la vente.
  final String ownerId;

  /// Le titre du livre au moment de la mise en vente.
  ///
  /// Le titre est recopié dans la vente : la ligne de commande du
  /// prestataire de paiement le porte, et la page de vente l'affiche sans
  /// relire le manuscrit.
  final String title;

  /// Le prix du livre, en centimes.
  ///
  /// Le prix vaut zéro pour un livre gratuit : le droit est alors accordé
  /// sans paiement, et la ventilation est nulle. Un prix négatif n'est pas
  /// un prix : il est refusé à l'écriture.
  final int priceInCents;

  /// La devise du prix.
  final String currency;

  /// L'état de la vente.
  final BookSaleStatus status;

  /// La part de l'auteur, en millièmes.
  final int authorShare;

  /// La part de la plateforme, en millièmes.
  final int platformShare;

  /// La clé du fichier vendu dans le stockage objet, `null` quand elle
  /// n'est pas connue.
  ///
  /// La clé est résolue au moment de la vente quand le livre n'en a pas
  /// encore : la page de téléchargement n'a alors pas à chercher le
  /// fichier à chaque appel.
  final String? artifactKey;

  /// L'instant de la création de la vente.
  final DateTime createdAt;

  /// L'instant de la dernière modification.
  final DateTime updatedAt;

  /// L'instant de la mise en vente, `null` quand le livre n'a jamais été
  /// publié.
  final DateTime? publishedAt;

  /// Le livre est-il en vente ?
  bool get isPublished => status == BookSaleStatus.published;

  /// Le livre est-il gratuit ?
  bool get isFree => priceInCents == 0;

  /// Renvoie une copie de la vente avec les champs remplacés.
  BookSaleRecord copyWith({
    String? title,
    int? priceInCents,
    String? currency,
    BookSaleStatus? status,
    int? authorShare,
    int? platformShare,
    String? artifactKey,
    DateTime? updatedAt,
    DateTime? publishedAt,
  }) {
    return BookSaleRecord(
      projectId: projectId,
      ownerId: ownerId,
      title: title ?? this.title,
      priceInCents: priceInCents ?? this.priceInCents,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      authorShare: authorShare ?? this.authorShare,
      platformShare: platformShare ?? this.platformShare,
      artifactKey: artifactKey ?? this.artifactKey,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      publishedAt: publishedAt ?? this.publishedAt,
    );
  }

  /// La représentation JSON de la vente, envoyée aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'project_id': projectId,
      'owner_id': ownerId,
      'title': title,
      'price_cents': priceInCents,
      'currency': currency,
      'status': status.key,
      'author_share': authorShare,
      'platform_share': platformShare,
      'is_free': isFree,
      'published_at': publishedAt?.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}

/// Le port de persistance des ventes de livres.
///
/// Le port ne porte aucune règle métier : la validité du prix, de la
/// devise et de l'état sont vérifiées par le service de vente.
abstract interface class BookSaleStore {
  /// La vente du livre [projectId], `null` quand le livre n'est pas en
  /// vente.
  Future<BookSaleRecord?> findByProject(String projectId);

  /// Enregistre la vente d'un livre.
  ///
  /// L'écriture remplace la vente précédente : un livre a un prix, pas
  /// deux.
  Future<void> save(BookSaleRecord record);

  /// Les ventes du compte [ownerId], les plus récentes d'abord.
  Future<List<BookSaleRecord>> listByOwner(String ownerId);
}
