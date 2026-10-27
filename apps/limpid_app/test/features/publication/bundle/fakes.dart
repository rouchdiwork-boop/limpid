import 'package:limpid_app/src/domain/bundle_repository.dart';
import 'package:limpid_app/src/features/publication/sale/payment_opener.dart';

/// Un depot de bundles que le test pilote.
///
/// Le faux tient ce que le serveur enverrait : le bundle et la commande. Il
/// compte aussi les appels, pour que le test verifie que le bouton a bien
/// commande le bundle.
final class FakeBundleRepository implements BundleRepository {
  /// Cree un depot servant [bundle] et [orderToServe].
  FakeBundleRepository({
    this.bundle,
    this.orderToServe = const BundleOrder(
      bundleId: 'bundle-1',
      amountInCents: 1500,
      currency: 'eur',
      isFree: false,
      paymentUrl: 'https://paiement.test/achat/1',
    ),
  });

  /// Le bundle servi, `null` quand le bundle n'est pas en vente.
  Bundle? bundle;

  /// La commande servie.
  BundleOrder orderToServe;

  /// L'erreur que la lecture du bundle leve, quand elle est posee.
  Object? bundleError;

  /// L'erreur que la commande leve, quand elle est posee.
  Object? orderError;

  /// Le nombre de lectures du bundle.
  int bundleCalls = 0;

  /// Le nombre de commandes.
  int orderCalls = 0;

  /// Le bundle commande.
  String? orderedBundleId;

  /// Le chemin de retour apres le paiement.
  String? orderedSuccessPath;

  /// Le chemin d'abandon du paiement.
  String? orderedCancelPath;

  @override
  Future<Bundle?> bundleOf(String bundleId) async {
    bundleCalls += 1;
    final Object? failure = bundleError;
    if (failure != null) throw failure;
    return bundle;
  }

  @override
  Future<BundleOrder> order({
    required String bundleId,
    required String successPath,
    required String cancelPath,
  }) async {
    orderCalls += 1;
    orderedBundleId = bundleId;
    orderedSuccessPath = successPath;
    orderedCancelPath = cancelPath;
    final Object? failure = orderError;
    if (failure != null) throw failure;
    return orderToServe;
  }
}

/// Un paiement que le test pilote.
///
/// Le faux note les adresses ouvertes : le test verifie que le bouton
/// « Acheter » a bien ouvert celle que le serveur a renvoyee.
final class FakeBundlePaymentOpener implements PaymentOpener {
  /// Les adresses ouvertes, dans l'ordre.
  final List<Uri> opened = <Uri>[];

  /// La plateforme sait-elle ouvrir une adresse de paiement ?
  bool canOpen = true;

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return canOpen;
  }
}

/// Le bundle des tests.
Bundle fakeBundle({
  String id = 'bundle-1',
  String title = 'Les deux livres',
  String description = 'Un ensemble.',
  int priceInCents = 1500,
  bool isPublished = true,
}) {
  return Bundle(
    id: id,
    title: title,
    description: description,
    books: <BundleBook>[
      const BundleBook(projectId: 'heures', title: 'Les Heures de Cendre'),
      const BundleBook(projectId: 'nuit', title: 'La Nuit des Savoirs'),
    ],
    priceInCents: priceInCents,
    currency: 'eur',
    isPublished: isPublished,
  );
}
