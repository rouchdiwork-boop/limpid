import 'dart:typed_data';

import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/features/publication/purchases/book_file_saver.dart';
import 'package:limpid_app/src/features/publication/sale/payment_opener.dart';

/// Un depot de vente que le test pilote.
///
/// Le faux tient ce que le serveur enverrait : la vente, la commande, les
/// achats et le fichier. Il compte aussi les appels, pour que le test
/// verifie que le bouton a bien commande le livre.
final class FakeBookSaleRepository implements BookSaleRepository {
  /// Cree un depot servant [sale], [purchased] et [file].
  FakeBookSaleRepository({
    this.sale,
    this.purchased = const <BookPurchase>[],
    this.file,
    this.orderToServe = const BookOrder(
      projectId: 'heures',
      amountInCents: 1290,
      currency: 'eur',
      isFree: false,
      paymentUrl: 'https://paiement.test/achat/1',
    ),
  });

  /// La vente servie, `null` quand le livre n'est pas en vente.
  BookSale? sale;

  /// Les achats servis.
  List<BookPurchase> purchased;

  /// Le fichier servi.
  BookFile? file;

  /// La commande servie.
  BookOrder orderToServe;

  /// L'erreur que la lecture de la vente leve, quand elle est posee.
  Object? saleError;

  /// L'erreur que la commande leve, quand elle est posee.
  Object? orderError;

  /// L'erreur que la lecture des achats leve, quand elle est posee.
  Object? purchasesError;

  /// L'erreur que le telechargement leve, quand elle est posee.
  Object? downloadError;

  /// Le nombre de lectures de la vente.
  int saleCalls = 0;

  /// Le nombre de commandes.
  int orderCalls = 0;

  /// Le nombre de lectures des achats.
  int purchasesCalls = 0;

  /// Le nombre de telechargements.
  int downloadCalls = 0;

  /// Le livre commande.
  String? orderedProjectId;

  /// Le chemin de retour apres le paiement.
  String? orderedSuccessPath;

  /// Le chemin d'abandon du paiement.
  String? orderedCancelPath;

  @override
  Future<BookSale?> saleOf(String projectId) async {
    saleCalls += 1;
    final Object? failure = saleError;
    if (failure != null) throw failure;
    return sale;
  }

  @override
  Future<BookOrder> order({
    required String projectId,
    required String successPath,
    required String cancelPath,
  }) async {
    orderCalls += 1;
    orderedProjectId = projectId;
    orderedSuccessPath = successPath;
    orderedCancelPath = cancelPath;
    final Object? failure = orderError;
    if (failure != null) throw failure;
    return orderToServe;
  }

  @override
  Future<List<BookPurchase>> purchases() async {
    purchasesCalls += 1;
    final Object? failure = purchasesError;
    if (failure != null) throw failure;
    return purchased;
  }

  @override
  Future<BookFile> download(String projectId) async {
    downloadCalls += 1;
    final Object? failure = downloadError;
    if (failure != null) throw failure;
    final BookFile? served = file;
    if (served == null) {
      throw const ApiNotFoundException("Ce livre n'a pas ete achete.");
    }
    return served;
  }
}

/// Un paiement que le test pilote.
///
/// Le faux note les adresses ouvertes : le test verifie que le bouton
/// « Acheter » a bien ouvert celle que le serveur a renvoyee.
final class FakePaymentOpener implements PaymentOpener {
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

/// Un enregistrement de fichier que le test pilote.
///
/// Le faux note les fichiers enregistres : le test verifie que le bouton
/// « Telecharger » a bien produit le fichier du livre.
final class FakeBookFileSaver implements BookFileSaver {
  /// Les fichiers enregistres, dans l'ordre.
  final List<BookFile> saved = <BookFile>[];

  /// L'erreur que l'enregistrement leve, quand elle est posee.
  Object? error;

  @override
  Future<void> save(BookFile file) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    saved.add(file);
  }
}

/// La vente du livre des tests.
BookSale fakeBookSale({
  String projectId = 'heures',
  String title = 'Les Heures de Cendre',
  int priceInCents = 1290,
  BookSaleStatus status = BookSaleStatus.published,
}) {
  return BookSale(
    projectId: projectId,
    title: title,
    priceInCents: priceInCents,
    currency: 'eur',
    status: status,
  );
}

/// L'achat d'un livre, pour les tests.
BookPurchase fakeBookPurchase({
  String projectId = 'heures',
  String title = 'Les Heures de Cendre',
  DateTime? grantedAt,
}) {
  return BookPurchase(
    projectId: projectId,
    title: title,
    grantedAt: grantedAt ?? DateTime.utc(2026, 3, 12),
    amountInCents: 1290,
    currency: 'eur',
  );
}

/// Le fichier d'un livre achete, pour les tests.
BookFile fakeBookFile({
  String projectId = 'heures',
  String fileName = 'heures.epub',
  DateTime? expiresAt,
}) {
  return BookFile(
    projectId: projectId,
    fileName: fileName,
    bytes: Uint8List.fromList(<int>[1, 2, 3]),
    expiresAt: expiresAt ?? DateTime.now().toUtc().add(const Duration(days: 1)),
  );
}
