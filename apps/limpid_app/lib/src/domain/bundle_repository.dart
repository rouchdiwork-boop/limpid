/// Le bundle : un ensemble de livres vendu comme un seul produit.
///
/// Le contrat vit dans la couche domaine : l'écran du bundle le nomme,
/// l'implémentation de la couche données le réalise — aucun des deux ne
/// connaît l'autre. Les types qu'ils manipulent sont **immuables** : l'écran
/// lit un état, il ne le modifie jamais.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// Un livre du bundle.
///
/// Le livre est nommé par son identifiant et par le titre qu'il portait au
/// moment de la mise en vente : c'est le titre que le lecteur voit dans la
/// vitrine.
@immutable
final class BundleBook {
  /// Crée un livre du bundle.
  const BundleBook({required this.projectId, required this.title});

  /// L'identifiant du livre.
  final String projectId;

  /// Le titre du livre.
  final String title;
}

/// Le bundle : ses livres, son prix, et son état de vente.
///
/// Le prix est lu **dans la base du serveur** : le client ne l'invente
/// jamais, et un bundle qui n'est pas en vente n'a pas de prix.
@immutable
final class Bundle {
  /// Crée un bundle.
  const Bundle({
    required this.id,
    required this.title,
    required this.description,
    required this.books,
    required this.priceInCents,
    required this.currency,
    required this.isPublished,
  });

  /// L'identifiant du bundle.
  final String id;

  /// Le titre du bundle.
  final String title;

  /// La description du bundle.
  final String description;

  /// Les livres du bundle, dans l'ordre du bundle.
  final List<BundleBook> books;

  /// Le prix du bundle, en centimes.
  final int priceInCents;

  /// La devise du prix.
  final String currency;

  /// Le bundle est-il en vente ?
  final bool isPublished;

  /// Le bundle est-il gratuit ?
  ///
  /// Un bundle gratuit n'ouvre aucune session de paiement : les droits de
  /// lecture sont accordés tout de suite.
  bool get isFree => priceInCents == 0;
}

/// La commande d'un bundle.
///
/// La commande porte l'adresse du paiement à ouvrir. Elle ne porte jamais
/// un prix venu du client : le serveur lit le prix dans sa base.
@immutable
final class BundleOrder {
  /// Crée une commande.
  const BundleOrder({
    required this.bundleId,
    required this.amountInCents,
    required this.currency,
    required this.isFree,
    this.paymentUrl,
    this.isGranted = false,
  });

  /// Le bundle commandé.
  final String bundleId;

  /// Le montant à payer, en centimes.
  final int amountInCents;

  /// La devise du montant.
  final String currency;

  /// Le bundle est-il gratuit ?
  final bool isFree;

  /// L'adresse du paiement, `null` quand le bundle est gratuit.
  ///
  /// Une adresse vide **et** un `null` sont deux refus : l'écran ne les
  /// confond jamais avec un paiement commencé.
  final String? paymentUrl;

  /// Les droits de lecture sont-ils accordés ?
  ///
  /// Ils le sont pour un bundle gratuit, et pour un bundle payé seulement
  /// quand le serveur a confirmé le paiement.
  final bool isGranted;

  /// L'adresse du paiement est-elle exploitable ?
  bool get hasPaymentUrl => (paymentUrl ?? '').isNotEmpty;
}

/// Le port des bundles.
///
/// L'écran du bundle lit ce port et n'atteint jamais le serveur. La
/// doublure par défaut refuse : un écran ne présente jamais un bundle, un
/// prix ou un achat que le serveur n'a pas envoyé.
abstract interface class BundleRepository {
  /// Le bundle [bundleId], `null` quand il n'est pas en vente.
  ///
  /// Un bundle absent de la vente n'a pas de prix : l'écran le dit et ne
  /// montre aucun montant.
  Future<Bundle?> bundleOf(String bundleId);

  /// Commande le bundle [bundleId] pour le compte.
  ///
  /// Le lecteur est renvoyé sur [successPath] quand le paiement aboutit, et
  /// sur [cancelPath] quand il l'abandonne. Les deux chemins sont des
  /// chemins de l'application : le port ne connaît pas son adresse publique.
  ///
  /// Lève `ServiceUnavailableException` quand le service de paiement n'est
  /// pas configuré sur ce poste : l'écran le dit au lieu de laisser croire
  /// qu'un paiement a commencé.
  Future<BundleOrder> order({
    required String bundleId,
    required String successPath,
    required String cancelPath,
  });
}

/// Un dépôt qui ne peut pas atteindre le serveur.
///
/// La page du bundle s'appuie sur lui pour dire qu'un bundle n'est pas en
/// vente : elle ne montre aucun prix et n'ouvre aucun paiement. Les autres
/// lectures refusent, et disent pourquoi.
final class UnavailableBundleRepository implements BundleRepository {
  /// Crée le dépôt.
  const UnavailableBundleRepository();

  @override
  Future<Bundle?> bundleOf(String bundleId) async => null;

  @override
  Future<BundleOrder> order({
    required String bundleId,
    required String successPath,
    required String cancelPath,
  }) async {
    throw const ServiceUnavailableException();
  }
}

/// Le dépôt des bundles.
///
/// La composition racine remplace ce port par l'implémentation qui lit
/// l'API. Le défaut refuse les écritures et dit pourquoi : l'écran du
/// bundle ne présente jamais un achat que le serveur n'a pas confirmé.
final Provider<BundleRepository> bundleRepositoryProvider =
    Provider<BundleRepository>((Ref ref) {
      return const UnavailableBundleRepository();
    });
