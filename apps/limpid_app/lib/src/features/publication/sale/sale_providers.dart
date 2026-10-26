import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';

/// La vente d'un livre.
///
/// Le provider lit le port de la vente : le prix vient du serveur, et un
/// livre qui n'est pas en vente n'a pas de prix. La page de vente et la
/// vitrine lisent tous les deux ce provider : la vitrine propose l'achat
/// quand le livre est en vente, et la page de vente montre le prix.
final bookSaleProvider = FutureProvider.family<BookSale?, String>((
  Ref ref,
  String projectId,
) async {
  final BookSaleRepository repository = ref.watch(bookSaleRepositoryProvider);
  return repository.saleOf(projectId);
});

/// Les livres achetés par le compte.
///
/// C'est cette liste qui **fait foi** : l'écran de retour du paiement ne
/// croit jamais l'adresse qui l'a ramené, il regarde ce que le compte a
/// réellement acheté.
final bookPurchasesProvider = FutureProvider<List<BookPurchase>>((
  Ref ref,
) async {
  final BookSaleRepository repository = ref.watch(bookSaleRepositoryProvider);
  return repository.purchases();
});
