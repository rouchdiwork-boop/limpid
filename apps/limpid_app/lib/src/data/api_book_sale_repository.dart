import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// La durée pendant laquelle deux commandes du même livre partagent la même
/// clé d'idempotence, en millisecondes.
///
/// Quinze minutes : assez pour absorber un double-clic, trop court pour
/// ressusciter une session de paiement expirée.
const int bookCheckoutKeyWindowMs = 15 * 60 * 1000;

/// Le nombre d'octets de l'entropie du nonce d'une commande.
const int _nonceBytes = 16;

/// Le nom du fichier d'un livre, quand le serveur n'en donne pas d'utile.
///
/// Le fichier d'un livre est un EPUB : le nom reprend l'extension du
/// livre, et le serveur n'a pas à le dire.
const String defaultBookFileName = 'livre.epub';

/// La vente des livres, servie par l'API.
///
/// Les quatre routes décrivent le cycle de vente : le prix du livre, la
/// commande en paiement unique, les livres achetés par le compte et le
/// fichier d'un livre acheté.
///
/// Le client ne laisse jamais sortir une exception brute : un échec est
/// toujours l'un des types de `domain/errors.dart`, ou
/// `ServiceUnavailableException` quand le paiement n'est pas configuré.
final class ApiBookSaleRepository implements BookSaleRepository {
  /// Crée un dépôt sur le dessus de [client].
  ///
  /// [checkoutOrigin] est l'adresse publique de l'application : le serveur
  /// l'emploie pour renvoyer l'acheteur vers l'écran de retour après le
  /// paiement. Sans elle, la commande ne peut pas s'ouvrir.
  ApiBookSaleRepository({
    required this.client,
    this.checkoutOrigin,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _nonce = _newNonce();

  /// Le client de l'API.
  final ApiClient client;

  /// L'origine publique de l'application, quand elle est connue.
  final Uri? checkoutOrigin;

  /// L'heure courante.
  final DateTime Function() _clock;

  /// Le nonce du dépôt, tiré une fois pour toutes.
  final String _nonce;

  @override
  Future<BookSale?> saleOf(String projectId) async {
    final String path = '/v1/books/${Uri.encodeComponent(projectId)}/sale';
    try {
      final Object? payload = await client.get(path);
      return _saleOf(payload);
    } on ApiUnauthorizedException {
      // Le lecteur n'a pas de compte : la page de vente est publique, et
      // le prix se lit sur la route publique — elle ne montre que les
      // livres en vente.
      return _publicSaleOf(projectId);
    } on ApiNotFoundException {
      // Un livre qui n'est pas en vente n'a pas de prix : l'écran le dit
      // et ne montre aucun montant.
      return null;
    }
  }

  /// Le prix public du livre [projectId], `null` quand il n'est pas en
  /// vente.
  ///
  /// La route publique ne dit rien d'un livre en préparation : elle
  /// répond la même chose qu'un livre inconnu.
  Future<BookSale?> _publicSaleOf(String projectId) async {
    try {
      final Object? payload = await client.get(
        '/v1/public/books/${Uri.encodeComponent(projectId)}/sale',
      );
      return _saleOf(payload);
    } on ApiNotFoundException {
      return null;
    }
  }

  @override
  Future<BookOrder> order({
    required String projectId,
    required String successPath,
    required String cancelPath,
  }) async {
    final Uri? origin = checkoutOrigin;
    if (origin == null) {
      // L'application ne connaît pas son adresse publique : elle ne peut
      // pas renvoyer l'acheteur vers l'écran de retour après le paiement.
      throw const ServiceUnavailableException();
    }
    final Object? payload = await client.post(
      '/v1/checkout/book',
      body: <String, Object?>{
        'project_id': projectId,
        'success_url': origin.resolve(successPath).toString(),
        'cancel_url': origin.resolve(cancelPath).toString(),
      },
      // Un double-clic sur « Acheter » ne doit pas ouvrir deux sessions de
      // paiement : la clé d'idempotence fait rejouer la première réponse
      // au lieu de créer une seconde session.
      headers: <String, String>{
        'idempotency-key': _idempotencyKeyOf(projectId),
      },
    );
    return _orderOf(payload);
  }

  @override
  Future<List<BookPurchase>> purchases() async {
    final Object? payload = await client.get('/v1/purchases');
    if (payload is! List<Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the list of the purchases.',
      );
    }
    return List<BookPurchase>.unmodifiable(payload.map(_purchaseOf));
  }

  @override
  Future<BookFile> download(String projectId) async {
    final Object? payload = await client.get(
      '/v1/purchases/${Uri.encodeComponent(projectId)}/download',
    );
    final Map<String, Object?> data = _objectOf(payload);
    final String url = _stringOf(data['download_url']) ?? '';
    if (url.isEmpty) {
      throw const ApiMalformedResponseException(
        'The API did not return the download address.',
      );
    }
    final DateTime expiresAt =
        _momentOf(data['expires_at']) ?? DateTime.now().toUtc();
    // L'adresse est **signée** : elle porte sa propre autorisation. Le
    // client n'y joint ni le jeton de session, ni la preuve du second
    // facteur : les envoyer à un hôte tiers les lui donnerait.
    final http.Response response = await client.download(Uri.parse(url));
    return BookFile(
      projectId: _stringOf(data['project_id']) ?? projectId,
      fileName: _fileNameOf(_stringOf(data['artifact_key']) ?? ''),
      bytes: Uint8List.fromList(response.bodyBytes),
      expiresAt: expiresAt,
    );
  }

  /// La vente portée par la réponse de l'API.
  ///
  /// Le prix et la devise sont **exigés** : une réponse qui ne les porte
  /// pas est une réponse malformée, et une page de vente qui afficherait
  /// un prix de zéro ferait passer un livre payant pour un livre gratuit.
  BookSale _saleOf(Object? payload) {
    final Map<String, Object?> data = _objectOf(payload);
    final int? price = _intOf(data['price_cents']);
    if (price == null) {
      throw const ApiMalformedResponseException(
        'The API did not return the price of the book.',
      );
    }
    final String? currency = _stringOf(data['currency']);
    if (currency == null || currency.isEmpty) {
      throw const ApiMalformedResponseException(
        'The API did not return the currency of the book.',
      );
    }
    return BookSale(
      projectId: _stringOf(data['project_id']) ?? '',
      title: _stringOf(data['title']) ?? '',
      priceInCents: price,
      currency: currency,
      status:
          BookSaleStatus.fromKey(_stringOf(data['status']) ?? '') ??
          BookSaleStatus.draft,
    );
  }

  /// La commande portée par la réponse de l'API.
  BookOrder _orderOf(Object? payload) {
    final Map<String, Object?> data = _objectOf(payload);
    return BookOrder(
      projectId: _stringOf(data['project_id']) ?? '',
      amountInCents: _intOf(data['amount_cents']) ?? 0,
      currency: _stringOf(data['currency']) ?? 'eur',
      isFree: data['is_free'] == true,
      paymentUrl: _stringOf(data['url']),
      isGranted: data['granted'] == true,
    );
  }

  /// Un achat porté par la réponse de l'API.
  BookPurchase _purchaseOf(Object? raw) {
    final Map<String, Object?> data = _objectOf(raw);
    return BookPurchase(
      projectId: _stringOf(data['project_id']) ?? '',
      title: _stringOf(data['title']) ?? '',
      grantedAt: _momentOf(data['granted_at']) ?? DateTime.now().toUtc(),
      amountInCents: _intOf(data['amount_cents']) ?? 0,
      currency: _stringOf(data['currency']) ?? 'eur',
      // La provenance de l'achat : un livre acheté par un bundle montre le
      // bundle qui l'a donné.
      bundleId: _stringOf(data['bundle_id']),
      bundleTitle: _stringOf(data['bundle_title']),
    );
  }

  /// Le nom du fichier, déduit de la clé de l'artefact.
  ///
  /// Le nom ne garde que le dernier segment de la clé : un serveur ne
  /// décide pas du chemin d'écriture sur le poste de l'acheteur.
  String _fileNameOf(String artifactKey) {
    final int slash = artifactKey.lastIndexOf('/');
    final String name = slash >= 0
        ? artifactKey.substring(slash + 1)
        : artifactKey;
    if (name.isEmpty || name == '.' || name == '..') {
      return defaultBookFileName;
    }
    return name;
  }

  /// La clé d'idempotence d'une commande.
  ///
  /// La clé tient dans une **fenêtre de temps** : deux clics dans la même
  /// fenêtre jouent la même commande, et une commande reprise plus tard
  /// ouvre une session neuve.
  String _idempotencyKeyOf(String projectId) {
    final int window =
        _clock().toUtc().millisecondsSinceEpoch ~/ bookCheckoutKeyWindowMs;
    return 'book-$_nonce-$projectId-$window';
  }

  /// Tire un nonce qui rend la clé d'idempotence opaque.
  static String _newNonce() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(
      _nonceBytes,
      (int _) => random.nextInt(256),
      growable: false,
    );
    return bytes
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Lit un objet JSON, ou refuse la réponse.
  Map<String, Object?> _objectOf(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const ApiMalformedResponseException(
      'The API did not return the expected payload.',
    );
  }

  /// Lit un texte, `null` quand le serveur n'en envoie pas.
  String? _stringOf(Object? value) => value is String ? value : null;

  /// Lit un nombre, `null` quand le serveur n'en envoie pas.
  int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  /// Lit un instant, `null` quand le serveur n'en envoie pas.
  DateTime? _momentOf(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
