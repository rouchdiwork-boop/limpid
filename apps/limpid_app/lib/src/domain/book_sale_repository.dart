/// La vente des livres : le prix, la commande, les achats et le fichier.
///
/// Le contrat vit dans la couche domaine : l'écran de vente le nomme,
/// l'implémentation de la couche données le réalise — aucun des deux ne
/// connaît l'autre. Les types qu'ils manipulent sont **immuables** : l'écran
/// lit un état, il ne le modifie jamais.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// L'état de la vente d'un livre.
///
/// Les états sont ceux du serveur : un livre se prépare, se publie, puis se
/// retire. Un livre dans un état inconnu n'est **pas** en vente : l'écran
/// ne montre alors ni prix ni bouton d'achat.
enum BookSaleStatus {
  /// Le livre se prépare : il n'est pas encore en vente.
  draft,

  /// Le livre est en vente.
  published,

  /// Le livre a été retiré de la vente.
  withdrawn;

  /// L'état nommé [raw], `null` quand le nom est inconnu.
  static BookSaleStatus? fromKey(String raw) {
    final String normalized = raw.trim().toLowerCase();
    for (final BookSaleStatus status in BookSaleStatus.values) {
      if (status.name == normalized) return status;
    }
    return null;
  }
}

/// La vente d'un livre : son prix, sa devise et l'état de la vente.
///
/// Le prix est lu **dans la base du serveur** : le client ne l'invente
/// jamais, et un livre qui n'est pas en vente n'a pas de prix.
@immutable
final class BookSale {
  /// Crée une vente.
  const BookSale({
    required this.projectId,
    required this.title,
    required this.priceInCents,
    required this.currency,
    required this.status,
  });

  /// Le livre vendu.
  final String projectId;

  /// Le titre du livre, tel qu'il est en vente aujourd'hui.
  final String title;

  /// Le prix du livre, en centimes.
  final int priceInCents;

  /// La devise du prix.
  final String currency;

  /// L'état de la vente.
  final BookSaleStatus status;

  /// Le livre est-il en vente ?
  bool get isPublished => status == BookSaleStatus.published;

  /// Le livre est-il gratuit ?
  ///
  /// Un livre gratuit n'ouvre aucune session de paiement : le droit de
  /// lecture est accordé tout de suite.
  bool get isFree => priceInCents == 0;
}

/// La commande d'un livre.
///
/// La commande porte l'adresse du paiement à ouvrir. Elle ne porte jamais
/// un prix venu du client : le serveur lit le prix dans sa base.
@immutable
final class BookOrder {
  /// Crée une commande.
  const BookOrder({
    required this.projectId,
    required this.amountInCents,
    required this.currency,
    required this.isFree,
    this.paymentUrl,
    this.isGranted = false,
  });

  /// Le livre commandé.
  final String projectId;

  /// Le montant à payer, en centimes.
  final int amountInCents;

  /// La devise du montant.
  final String currency;

  /// Le livre est-il gratuit ?
  final bool isFree;

  /// L'adresse du paiement, `null` quand le livre est gratuit.
  ///
  /// Une adresse vide **et** un `null` sont deux refus : l'écran ne les
  /// confond jamais avec un paiement commencé.
  final String? paymentUrl;

  /// Le droit de lecture est-il accordé ?
  ///
  /// Il l'est pour un livre gratuit, et pour un livre payé seulement quand
  /// le serveur a confirmé le paiement.
  final bool isGranted;

  /// L'adresse du paiement est-elle exploitable ?
  bool get hasPaymentUrl => (paymentUrl ?? '').isNotEmpty;
}

/// Un livre acheté par le compte.
@immutable
final class BookPurchase {
  /// Crée un achat.
  const BookPurchase({
    required this.projectId,
    required this.title,
    required this.grantedAt,
    required this.amountInCents,
    required this.currency,
  });

  /// Le livre acheté.
  final String projectId;

  /// Le titre du livre, tel qu'il est en vente aujourd'hui.
  final String title;

  /// L'instant de l'achat.
  final DateTime grantedAt;

  /// Le montant payé, en centimes.
  final int amountInCents;

  /// La devise du montant.
  final String currency;
}

/// Le fichier d'un livre acheté.
///
/// Le fichier porte la **durée de vie** de l'adresse qui l'a servi :
/// l'écran la dit, et l'acheteur redemande une adresse quand elle a
/// expiré.
@immutable
final class BookFile {
  /// Crée un fichier.
  const BookFile({
    required this.projectId,
    required this.fileName,
    required this.bytes,
    required this.expiresAt,
  });

  /// Le livre téléchargé.
  final String projectId;

  /// Le nom du fichier, prêt à être enregistré.
  ///
  /// Le nom ne porte jamais de chemin : il vient du serveur, et un serveur
  /// ne décide pas où un fichier s'écrit sur le poste de l'acheteur.
  final String fileName;

  /// Le contenu du fichier.
  ///
  /// Le fichier est binaire : il ne peut pas passer par le presse-papiers,
  /// et il se donne tel quel au navigateur ou au systeme de fichiers.
  final Uint8List bytes;

  /// L'instant où l'adresse de téléchargement expire.
  final DateTime expiresAt;

  /// L'adresse a-t-elle expiré ?
  bool isExpiredAt(DateTime moment) => !expiresAt.isAfter(moment);
}

/// Le port de la vente des livres.
///
/// L'écran de vente et l'écran des achats lisent ce port et n'atteignent
/// jamais le serveur. La doublure par défaut refuse : un écran ne présente
/// jamais un prix, un achat ou un fichier que le serveur n'a pas envoyé.
abstract interface class BookSaleRepository {
  /// La vente du livre [projectId], `null` quand il n'est pas en vente.
  ///
  /// Un livre absent de la vente n'a pas de prix : l'écran le dit et ne
  /// montre aucun montant.
  Future<BookSale?> saleOf(String projectId);

  /// Commande le livre [projectId] pour le compte.
  ///
  /// Le lecteur est renvoyé sur [successPath] quand le paiement aboutit, et
  /// sur [cancelPath] quand il l'abandonne. Les deux chemins sont des
  /// chemins de l'application : le port ne connaît pas son adresse publique.
  ///
  /// Lève `ServiceUnavailableException` quand le service de paiement n'est
  /// pas configuré sur ce poste : l'écran le dit au lieu de laisser croire
  /// qu'un paiement a commencé.
  Future<BookOrder> order({
    required String projectId,
    required String successPath,
    required String cancelPath,
  });

  /// Les livres achetés par le compte, les plus récents d'abord.
  Future<List<BookPurchase>> purchases();

  /// Le fichier du livre [projectId] acheté par le compte.
  ///
  /// Lève une erreur typée quand le compte n'a pas acheté le livre, ou
  /// quand le serveur n'a pas pu produire le fichier.
  Future<BookFile> download(String projectId);
}

/// Un dépôt qui ne peut pas atteindre le serveur.
///
/// La page de vente s'appuie sur lui pour dire qu'un livre n'est pas en
/// vente : elle ne montre aucun prix et n'ouvre aucun paiement. Les autres
/// lectures refusent, et disent pourquoi.
final class UnavailableBookSaleRepository implements BookSaleRepository {
  /// Crée le dépôt.
  const UnavailableBookSaleRepository();

  @override
  Future<BookSale?> saleOf(String projectId) async => null;

  @override
  Future<BookOrder> order({
    required String projectId,
    required String successPath,
    required String cancelPath,
  }) async {
    throw const ServiceUnavailableException();
  }

  @override
  Future<List<BookPurchase>> purchases() async {
    throw const ServiceUnavailableException();
  }

  @override
  Future<BookFile> download(String projectId) async {
    throw const ServiceUnavailableException();
  }
}

/// Le dépôt de la vente des livres.
///
/// La composition racine remplace ce port par l'implémentation qui lit
/// l'API. Le défaut refuse les écritures et dit pourquoi : l'écran de vente
/// ne présente jamais un achat que le serveur n'a pas confirmé.
final Provider<BookSaleRepository> bookSaleRepositoryProvider =
    Provider<BookSaleRepository>((Ref ref) {
      return const UnavailableBookSaleRepository();
    });
