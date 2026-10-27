import '../db/book_sale_store.dart';
import '../db/kdp_database.dart';
import '../db/kdp_record.dart';
import '../dependencies.dart';

/// Les métadonnées commerciales publiées d'un livre.
///
/// Les métadonnées viennent de la **publication préparée** : c'est
/// l'instantané que l'auteur a publié pour son livre, et il fait foi — ce
/// que l'auteur saisit après coup ne le change pas. Le prix et la date de
/// publication viennent de la **mise en vente** : une vente en cours est
/// elle-même une publication commerciale.
///
/// Une métadonnée que l'auteur n'a pas publiée n'apparaît pas : la page
/// publique ne montre que ce qui a été dit.
final class PublishedMetadata {
  /// Crée un ensemble de métadonnées publiées.
  const PublishedMetadata({
    this.isbn,
    this.publisher,
    this.description,
    this.language,
    this.contributors = const <String>[],
    this.keywords = const <String>[],
    this.categories = const <String>[],
    this.priceInCents,
    this.currency,
    this.publishedAt,
  });

  /// L'ISBN de l'édition publiée.
  final String? isbn;

  /// L'éditeur de l'ouvrage.
  final String? publisher;

  /// Le résumé public de l'ouvrage.
  final String? description;

  /// La langue de l'ouvrage.
  final String? language;

  /// Les personnes qui ont écrit l'ouvrage.
  final List<String> contributors;

  /// Les mots-clés de la fiche produit.
  final List<String> keywords;

  /// Les catégories BISAC de la fiche produit.
  final List<String> categories;

  /// Le prix du livre, en centimes.
  final int? priceInCents;

  /// La devise du prix.
  final String? currency;

  /// La date de publication du livre.
  final DateTime? publishedAt;

  /// Les métadonnées de la publication préparée et de la mise en vente.
  ///
  /// Une vente qui n'est pas en cours ne publie pas son prix : le livre
  /// retiré de la vente n'a plus de prix public.
  factory PublishedMetadata.of({
    KdpPublication? publication,
    BookSaleRecord? sale,
  }) {
    return PublishedMetadata(
      isbn: _text(publication?.isbn),
      publisher: _text(publication?.publisher),
      description: _text(publication?.description),
      language: _text(publication?.language),
      contributors: _contributors(publication),
      keywords: publication?.keywords ?? const <String>[],
      categories: publication?.categories ?? const <String>[],
      priceInCents: sale != null && sale.isPublished ? sale.priceInCents : null,
      currency: sale != null && sale.isPublished ? sale.currency : null,
      // La date de mise en vente suit le prix : un livre retire de la vente
      // n'a plus de prix, et n'a donc plus de date publique.
      publishedAt: sale != null && sale.isPublished ? sale.publishedAt : null,
    );
  }

  /// Vrai quand le livre n'a publié aucune métadonnée.
  bool get isEmpty =>
      isbn == null &&
      publisher == null &&
      description == null &&
      language == null &&
      contributors.isEmpty &&
      keywords.isEmpty &&
      categories.isEmpty &&
      priceInCents == null &&
      publishedAt == null;

  /// La représentation JSON envoyée aux lecteurs.
  ///
  /// Les métadonnées absentes sont omises : la page publique ne montre
  /// jamais une case vide.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (isbn != null) 'isbn': isbn,
      if (publisher != null) 'publisher': publisher,
      if (description != null) 'description': description,
      if (language != null) 'language': language,
      if (contributors.isNotEmpty) 'contributors': contributors,
      if (keywords.isNotEmpty) 'keywords': keywords,
      if (categories.isNotEmpty) 'categories': categories,
      if (priceInCents != null)
        'price': <String, Object?>{
          'amount': priceInCents,
          'currency': currency,
        },
      if (publishedAt != null)
        'publishedAt': publishedAt!.toUtc().toIso8601String(),
    };
  }

  /// Les personnes qui ont écrit l'ouvrage.
  static List<String> _contributors(KdpPublication? publication) {
    final String? author = _text(publication?.author);
    if (author == null) return const <String>[];
    return <String>[author];
  }

  /// La valeur [value] nettoyée, `null` quand elle ne porte rien.
  static String? _text(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Les métadonnées publiées du livre [projectId].
///
/// Les dépendances facultatives — la base des ventes, la base des
/// publications Amazon — ne sont pas toujours câblées : un serveur qui ne
/// les a pas publie un livre sans métadonnées, jamais une page cassée.
Future<PublishedMetadata> publishedMetadataOf(
  AppDependencies dependencies,
  String projectId,
) async {
  final KdpDatabase? kdp = dependencies.kdp;
  final KdpPublication? publication = kdp == null
      ? null
      : await kdp.findPublicationByProject(projectId: projectId);
  final BookSaleStore? sales = dependencies.bookSales;
  final BookSaleRecord? sale = sales == null
      ? null
      : await sales.findByProject(projectId);
  return PublishedMetadata.of(publication: publication, sale: sale);
}
