import 'dart:convert';

/// Le nombre minimal de livres d'un bundle.
///
/// Un bundle d'un seul livre est une vente simple, malaisiee : il
/// n'apporterait rien a l'acheteur et compliquerait la ventilation des
/// droits. Deux livres sont le minimum d'un ensemble.
const int minimumBundleBooks = 2;

/// Le bundle : un ensemble de livres vendu comme un seul produit.
///
/// Le bundle porte **un** vendeur : le compte qui le vend est l'auteur de
/// tous les livres qu'il contient. Un bundle qui melange les auteurs n'a pas
/// de vendeur, et la ventilation des droits n'a pas de sens.
///
/// Le prix est **fixe** : il ne se recalcule pas tout seul. La remise d'un
/// code promo s'y applique comme sur le prix d'un livre, et la ventilation
/// se fait sur le montant payé, jamais sur le prix posé.
///
/// Les livres sont dans l'ordre : c'est l'ordre dans lequel la page du
/// bundle les présente.
final class BundleRecord {
  /// Crée un bundle.
  const BundleRecord({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.description,
    required this.projectIds,
    required this.priceInCents,
    required this.currency,
    required this.isPublished,
    required this.createdAt,
  });

  /// L'identifiant du bundle.
  final String id;

  /// Le compte qui vend le bundle.
  ///
  /// Le vendeur est l'auteur de tous les livres du bundle : c'est lui qui
  /// encaisse la vente.
  final String ownerId;

  /// Le titre du bundle.
  final String title;

  /// La description du bundle.
  ///
  /// Elle est libre : une description vide est un bundle sans description,
  /// pas un bundle invalide.
  final String description;

  /// Les livres du bundle, dans l'ordre.
  final List<String> projectIds;

  /// Le prix du bundle, en centimes.
  ///
  /// Le prix est **posé** : il ne se recalcule pas à partir des prix des
  /// livres. Un prix nul fait un bundle gratuit : il se vend sans paiement,
  /// et sa ventilation est nulle.
  final int priceInCents;

  /// La devise du prix.
  final String currency;

  /// Le bundle est-il en vente ?
  final bool isPublished;

  /// L'instant de la création du bundle.
  final DateTime createdAt;

  /// Le bundle est-il en vente ?
  bool get isForSale => isPublished;

  /// Le bundle est-il gratuit ?
  bool get isFree => priceInCents == 0;

  /// Le bundle porte-t-il assez de livres ?
  bool get hasEnoughBooks => projectIds.length >= minimumBundleBooks;

  /// Renvoie une copie du bundle avec les champs remplacés.
  BundleRecord copyWith({
    String? title,
    String? description,
    List<String>? projectIds,
    int? priceInCents,
    String? currency,
    bool? isPublished,
  }) {
    return BundleRecord(
      id: id,
      ownerId: ownerId,
      title: title ?? this.title,
      description: description ?? this.description,
      projectIds: projectIds ?? this.projectIds,
      priceInCents: priceInCents ?? this.priceInCents,
      currency: currency ?? this.currency,
      isPublished: isPublished ?? this.isPublished,
      createdAt: createdAt,
    );
  }

  /// La représentation JSON du bundle, envoyée aux clients.
  ///
  /// La liste des livres est copiée : la réponse ne porte jamais la liste
  /// mutable du bundle.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'owner_id': ownerId,
      'title': title,
      'description': description,
      'project_ids': List<String>.unmodifiable(projectIds),
      'price_cents': priceInCents,
      'currency': currency,
      'is_published': isPublished,
      'is_free': isFree,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  /// La représentation JSON du bundle lue par un visiteur.
  ///
  /// Le vendeur ne fait pas partie du public : la page du bundle montre les
  /// livres, le titre et le prix, pas le compte qui encaisse.
  Map<String, Object?> toPublicJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'description': description,
      'project_ids': List<String>.unmodifiable(projectIds),
      'price_cents': priceInCents,
      'currency': currency,
      'is_published': isPublished,
      'is_free': isFree,
    };
  }
}

/// Encode la liste des livres du bundle pour la base.
String encodeBundleProjectIds(List<String> projectIds) {
  return jsonEncode(projectIds);
}

/// Décode la liste des livres du bundle lue de la base.
///
/// Une valeur absente ou illisible donne une liste vide : le bundle sera
/// refusé à la vente, plutôt que de vendre un ensemble inconnu.
List<String> decodeBundleProjectIds(Object? value) {
  final Object? decoded = value is String ? _decode(value) : value;
  if (decoded is! List) return const <String>[];
  return List<String>.unmodifiable(decoded.whereType<String>());
}

/// Décode un JSON de liste, et nomme la valeur fautive quand elle est
/// illisible.
Object? _decode(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException catch (error) {
    throw FormatException(
      'The list of the books of a bundle is not a valid JSON: ${error.message}',
    );
  }
}

/// Le port de persistance des bundles.
///
/// Le port ne porte aucune règle métier : le nombre de livres, leur mise en
/// vente et la propriété sont vérifiées par le service des bundles.
abstract interface class BundleStore {
  /// Le bundle [bundleId], `null` quand il n'existe pas.
  Future<BundleRecord?> findById(String bundleId);

  /// Enregistre le bundle.
  ///
  /// L'écriture remplace le bundle précédent : un bundle a un prix, pas
  /// deux.
  Future<void> save(BundleRecord record);

  /// Les bundles du compte [ownerId], les plus récents d'abord.
  Future<List<BundleRecord>> listByOwner(String ownerId);
}
