import 'dart:math';

import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/bundle_repository.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// La durée pendant laquelle deux commandes du même bundle partagent la même
/// clé d'idempotence, en millisecondes.
///
/// Quinze minutes : assez pour absorber un double-clic, trop court pour
/// ressusciter une session de paiement expirée.
const int bundleCheckoutKeyWindowMs = 15 * 60 * 1000;

/// Le nombre d'octets de l'entropie du nonce d'une commande.
const int _nonceBytes = 16;

/// Les bundles, servis par l'API.
///
/// Les trois routes décrivent le cycle du bundle : la lecture du bundle, la
/// commande en paiement unique, et les livres du bundle dans la réponse.
///
/// Le client ne laisse jamais sortir une exception brute : un échec est
/// toujours l'un des types de `domain/errors.dart`, ou
/// `ServiceUnavailableException` quand le paiement n'est pas configuré.
final class ApiBundleRepository implements BundleRepository {
  /// Crée un dépôt sur le dessus de [client].
  ///
  /// [checkoutOrigin] est l'adresse publique de l'application : le serveur
  /// l'emploie pour renvoyer l'acheteur vers l'écran de retour après le
  /// paiement. Sans elle, la commande ne peut pas s'ouvrir.
  ApiBundleRepository({
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
  Future<Bundle?> bundleOf(String bundleId) async {
    final String path = '/v1/bundles/${Uri.encodeComponent(bundleId)}';
    try {
      final Object? payload = await client.get(path);
      return _bundleOf(payload);
    } on ApiUnauthorizedException {
      // Le lecteur n'a pas de compte : la page du bundle est publique, et
      // le prix se lit sur la route publique — elle ne montre que les
      // bundles en vente.
      return _publicBundleOf(bundleId);
    } on ApiNotFoundException {
      // Un bundle qui n'est pas en vente n'a pas de prix : l'écran le dit
      // et ne montre aucun montant.
      return null;
    }
  }

  /// Le bundle public [bundleId], `null` quand il n'est pas en vente.
  ///
  /// La route publique ne dit rien d'un bundle en préparation : elle
  /// répond la même chose qu'un bundle inconnu.
  Future<Bundle?> _publicBundleOf(String bundleId) async {
    try {
      final Object? payload = await client.get(
        '/v1/public/bundles/${Uri.encodeComponent(bundleId)}',
      );
      return _bundleOf(payload);
    } on ApiNotFoundException {
      return null;
    }
  }

  @override
  Future<BundleOrder> order({
    required String bundleId,
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
      '/v1/checkout/bundle',
      body: <String, Object?>{
        'bundle_id': bundleId,
        'success_url': origin.resolve(successPath).toString(),
        'cancel_url': origin.resolve(cancelPath).toString(),
      },
      // Un double-clic sur « Acheter » ne doit pas ouvrir deux sessions de
      // paiement : la clé d'idempotence fait rejouer la première réponse
      // au lieu de créer une seconde session.
      headers: <String, String>{'idempotency-key': _idempotencyKeyOf(bundleId)},
    );
    return _orderOf(payload);
  }

  /// Le bundle porté par la réponse de l'API.
  ///
  /// Le prix et la devise sont **exigés** : une réponse qui ne les porte
  /// pas est une réponse malformée, et une page de bundle qui afficherait
  /// un prix de zéro ferait passer un bundle payant pour un bundle gratuit.
  Bundle _bundleOf(Object? payload) {
    final Map<String, Object?> data = _objectOf(payload);
    final int? price = _intOf(data['price_cents']);
    if (price == null) {
      throw const ApiMalformedResponseException(
        'The API did not return the price of the bundle.',
      );
    }
    final String? currency = _stringOf(data['currency']);
    if (currency == null || currency.isEmpty) {
      throw const ApiMalformedResponseException(
        'The API did not return the currency of the bundle.',
      );
    }
    return Bundle(
      id: _stringOf(data['id']) ?? '',
      title: _stringOf(data['title']) ?? '',
      description: _stringOf(data['description']) ?? '',
      books: _booksOf(data['books']),
      priceInCents: price,
      currency: currency,
      isPublished: data['is_published'] == true,
    );
  }

  /// Les livres du bundle portés par la réponse de l'API.
  ///
  /// La liste est **ordonnée** : l'ordre des livres fait partie du
  /// bundle, et le serveur l'envoie dans cet ordre.
  List<BundleBook> _booksOf(Object? raw) {
    if (raw is! List<Object?>) return const <BundleBook>[];
    final List<BundleBook> books = <BundleBook>[];
    for (final Object? value in raw) {
      if (value is! Map<String, Object?>) continue;
      final String? projectId = _stringOf(value['project_id']);
      if (projectId == null || projectId.isEmpty) continue;
      books.add(
        BundleBook(
          projectId: projectId,
          title: _stringOf(value['title']) ?? '',
        ),
      );
    }
    return List<BundleBook>.unmodifiable(books);
  }

  /// La commande portée par la réponse de l'API.
  BundleOrder _orderOf(Object? payload) {
    final Map<String, Object?> data = _objectOf(payload);
    return BundleOrder(
      bundleId: _stringOf(data['bundle_id']) ?? '',
      amountInCents: _intOf(data['amount_cents']) ?? 0,
      currency: _stringOf(data['currency']) ?? 'eur',
      isFree: data['is_free'] == true,
      paymentUrl: _stringOf(data['url']),
      isGranted: data['granted'] == true,
    );
  }

  /// La clé d'idempotence d'une commande.
  ///
  /// La clé tient dans une **fenêtre de temps** : deux clics dans la même
  /// fenêtre jouent la même commande, et une commande reprise plus tard
  /// ouvre une session neuve.
  String _idempotencyKeyOf(String bundleId) {
    final int window =
        _clock().toUtc().millisecondsSinceEpoch ~/ bundleCheckoutKeyWindowMs;
    return 'bundle-$_nonce-$bundleId-$window';
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
}
