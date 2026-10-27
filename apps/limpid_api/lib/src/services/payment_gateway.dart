import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:limpid_core/limpid_core.dart';

import '../errors/app_exception.dart';
import 'plan_catalog.dart';

/// Le suffixe qui porte le cycle annuel dans le nom d'une formule.
///
/// Le webhook de paiement lit le même suffixe : la clé d'une commande
/// annuelle reste `studio_yearly` des deux côtés.
const String yearlyPlanSuffix = '_yearly';

/// La marque qui distingue l'achat d'un livre de l'abonnement.
///
/// Le serveur l'écrit lui-même dans les métadonnées de la session : le
/// client ne peut pas la forger, et le webhook de paiement sait ainsi à
/// quelle commande il a affaire.
const String bookPaymentKind = 'book';

/// La marque qui distingue l'achat d'un bundle de l'achat d'un livre.
///
/// Comme la marque du livre, elle est écrite par le serveur : le client ne
/// peut pas la forger.
const String bundlePaymentKind = 'bundle';

/// Une session de paiement Stripe.
final class CheckoutSession {
  /// Crée une session.
  const CheckoutSession({
    required this.id,
    required this.url,
    required this.ownerId,
    this.status = 'open',
  });

  /// L'identifiant de la session.
  final String id;

  /// L'adresse vers laquelle l'acheteur est renvoyé.
  final String url;

  /// Le compte auquel la session appartient.
  ///
  /// Le propriétaire est relu avec la session : une session n'est jamais
  /// remise à un autre compte, et l'adresse du paiement reste le secret de
  /// celui qui l'a ouverte.
  final String ownerId;

  /// L'état de la session.
  final String status;

  /// La représentation JSON envoyée aux clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{'session_id': id, 'url': url, 'status': status};
  }
}

/// L'abonnement qu'une commande achète.
///
/// La commande porte la formule **et** son cycle : le prix, l'essai offert
/// et la clé lue par le webhook de paiement viennent tous du domaine
/// partagé (D-15). L'API ne garde pas une seconde liste de prix, qui
/// divergerait de celle que le client lit.
final class SubscriptionOrder {
  /// Crée une commande.
  ///
  /// La commande porte les invariants du domaine : elle achète une formule
  /// payante, sur un cycle que cette formule propose. Le constructeur refuse
  /// donc la formule gratuite, et le cycle annuel d'une formule qui ne le
  /// propose pas.
  SubscriptionOrder({required this.plan, required this.period}) {
    if (plan == SubscriptionPlan.free) {
      throw ValidationException(
        field: 'plan',
        message:
            'Le champ « plan » est refusé : la formule gratuite ne s\'achète '
            'pas, elle ne demande aucun paiement.',
        details: <String, Object?>{'field': 'plan'},
      );
    }
    if (period == BillingPeriod.yearly &&
        !PlanCatalog.offersYearlyCycle(plan)) {
      throw ValidationException(
        field: 'period',
        message:
            'Le champ « period » est refusé : la formule '
            '${PlanCatalog.definitionOf(plan).displayName} ne propose pas de '
            'cycle annuel.',
        details: <String, Object?>{'field': 'period'},
      );
    }
  }

  /// La formule achetée.
  final SubscriptionPlan plan;

  /// Le cycle de facturation acheté.
  final BillingPeriod period;

  /// La clé de la commande : le nom de la formule, suffixé du cycle annuel.
  ///
  /// C'est la clé que Stripe porte dans ses métadonnées, et celle que le
  /// webhook de paiement relit pour attribuer la formule et son cycle.
  String get key => period == BillingPeriod.yearly
      ? '${plan.name}$yearlyPlanSuffix'
      : plan.name;

  /// Le prix de la commande, en centimes.
  ///
  /// Le montant vient du domaine partagé : le cycle annuel d'une formule
  /// est chiffré par le domaine, pas par le serveur.
  int get priceInCents => PlanCatalog.definitionFor(plan, period).priceInCents;

  /// Le nom de la formule, tel que le catalogue l'écrit.
  String get displayName => PlanCatalog.definitionFor(plan, period).displayName;

  /// La durée de l'essai offert, en jours.
  ///
  /// Elle vaut zéro quand la formule n'en propose pas : l'essai de D-15 ne
  /// concerne que la formule Écrivain.
  int get trialDays => PlanCatalog.trialDaysOf(plan);

  /// L'intervalle récurrent que Stripe comprend pour ce cycle.
  String get stripeInterval =>
      period == BillingPeriod.yearly ? 'year' : 'month';

  /// La commande lue dans la clé de formule [planKey] et le cycle [period].
  ///
  /// La clé de la formule peut porter le suffixe annuel (`studio_yearly`) :
  /// le client qui porte le cycle dans le nom de la formule et le client qui
  /// le porte dans un champ à part sont tous deux compris. Le cycle [period]
  /// l'emporte quand la clé ne porte pas de suffixe ; une clé qui contredit
  /// le cycle demandé est refusée.
  ///
  /// Jette une [ValidationException] qui nomme le champ fautif quand la
  /// formule n'existe pas, quand elle ne propose pas le cycle annuel, ou
  /// quand la commande achète la formule gratuite : la formule gratuite ne
  /// s'achète pas.
  static SubscriptionOrder resolve({
    required String planKey,
    BillingPeriod? period,
  }) {
    final String normalized = planKey.trim().toLowerCase();
    String name = normalized;
    BillingPeriod? suffixed;
    if (name.endsWith(yearlyPlanSuffix)) {
      name = name.substring(0, name.length - yearlyPlanSuffix.length);
      suffixed = BillingPeriod.yearly;
    }
    final SubscriptionPlan? plan = _planByName(name);
    if (plan == null) {
      throw ValidationException(
        field: 'plan',
        message:
            'Le champ « plan » est refusé : la formule « $planKey » '
            'n\'existe pas.',
        details: <String, Object?>{'field': 'plan'},
      );
    }
    if (suffixed != null && period != null && suffixed != period) {
      throw ValidationException(
        field: 'period',
        message:
            'Le champ « period » est refusé : la formule « $normalized » est '
            'annuelle, le cycle demandé « ${period.name} » ne l\'est pas.',
        details: <String, Object?>{'field': 'period'},
      );
    }
    final BillingPeriod cycle = period ?? suffixed ?? BillingPeriod.monthly;
    // Le constructeur porte les invariants : la formule gratuite ne
    // s'achète pas, et une formule qui ne propose pas de cycle annuel ne
    // peut pas être achetée sur ce cycle.
    return SubscriptionOrder(plan: plan, period: cycle);
  }

  /// La formule nommée [name], `null` quand elle n'existe pas.
  static SubscriptionPlan? _planByName(String name) {
    for (final SubscriptionPlan candidate in SubscriptionPlan.values) {
      if (candidate.name == name) return candidate;
    }
    return null;
  }
}

/// Une demande de session de paiement.
final class CheckoutRequest {
  /// Crée une demande.
  const CheckoutRequest({
    required this.userId,
    required this.plan,
    required this.period,
    required this.successUrl,
    required this.cancelUrl,
    this.idempotencyKey,
    this.startTrial = false,
  });

  /// Le compte qui achète la formule.
  final String userId;

  /// La formule achetée.
  final SubscriptionPlan plan;

  /// Le cycle de facturation de l'abonnement.
  final BillingPeriod period;

  /// L'adresse sur laquelle l'acheteur arrive après un paiement réussi.
  final String successUrl;

  /// L'adresse sur laquelle l'acheteur arrive quand il abandonne le
  /// paiement.
  final String cancelUrl;

  /// La clé d'idempotence de l'appel, quand le client en a envoyé une.
  final String? idempotencyKey;

  /// L'abonnement commence-t-il par une période d'essai ?
  ///
  /// La décision appartient à l'appelant, qui connaît l'historique du
  /// compte : l'essai est accordé **une fois** (D-15).
  final bool startTrial;
}

/// La capacité de paiement de l'API.
abstract interface class PaymentGateway {
  /// Ouvre une session de paiement.
  Future<CheckoutSession> createSession(CheckoutRequest request);

  /// Relit une session de paiement, `null` quand elle n'existe pas.
  Future<CheckoutSession?> retrieveSession(String sessionId);
}

/// La demande de session de paiement d'un livre.
///
/// Un livre se paie **une fois** : la demande ne porte ni formule ni
/// cycle, mais un livre, un montant et une devise. Le montant est celui
/// que le serveur a lu dans sa base : le client ne peut pas le changer.
final class BookCheckoutRequest {
  /// Crée une demande.
  const BookCheckoutRequest({
    required this.userId,
    required this.projectId,
    required this.title,
    required this.priceInCents,
    required this.currency,
    required this.successUrl,
    required this.cancelUrl,
    this.idempotencyKey,
    this.promoCode,
  });

  /// Le compte qui achète le livre.
  final String userId;

  /// Le livre acheté.
  final String projectId;

  /// Le titre du livre, porté par la ligne de commande.
  final String title;

  /// Le montant à payer, en centimes.
  final int priceInCents;

  /// La devise du montant.
  final String currency;

  /// L'adresse sur laquelle l'acheteur arrive après un paiement réussi.
  final String successUrl;

  /// L'adresse sur laquelle l'acheteur arrive quand il abandonne le
  /// paiement.
  final String cancelUrl;

  /// La clé d'idempotence de l'appel, quand le client en a envoyé une.
  final String? idempotencyKey;

  /// Le code promo appliqué, `null` quand il n'y en a pas.
  final String? promoCode;
}

/// La demande de session de paiement d'un bundle.
///
/// Un bundle se paie **une fois**, comme un livre : la demande ne porte
/// ni formule ni cycle, mais un bundle, un montant et une devise. Le
/// montant est celui que le serveur a lu dans sa base : le client ne peut
/// pas le changer.
final class BundleCheckoutRequest {
  /// Crée une demande.
  const BundleCheckoutRequest({
    required this.userId,
    required this.bundleId,
    required this.title,
    required this.priceInCents,
    required this.currency,
    required this.successUrl,
    required this.cancelUrl,
    this.idempotencyKey,
    this.promoCode,
  });

  /// Le compte qui achète le bundle.
  final String userId;

  /// Le bundle acheté.
  final String bundleId;

  /// Le titre du bundle, porté par la ligne de commande.
  final String title;

  /// Le montant à payer, en centimes.
  final int priceInCents;

  /// La devise du montant.
  final String currency;

  /// L'adresse sur laquelle l'acheteur arrive après un paiement réussi.
  final String successUrl;

  /// L'adresse sur laquelle l'acheteur arrive quand il abandonne le
  /// paiement.
  final String cancelUrl;

  /// La clé d'idempotence de l'appel, quand le client en a envoyé une.
  final String? idempotencyKey;

  /// Le code promo appliqué, `null` quand il n'y en a pas.
  final String? promoCode;
}

/// La capacité de paiement d'une vente : un livre ou un bundle.
///
/// Elle est un **frère** de [PaymentGateway] et non une partie : une
/// passerelle qui ne sait pas vendre un livre — un serveur de test, une
/// passerelle d'un autre usage — n'a pas à l'implémenter. La route qui
/// vend un livre demande une [BookPaymentGateway] et refuse proprement
/// quand le serveur n'en a pas.
abstract interface class BookPaymentGateway {
  /// Ouvre une session de paiement unique pour un livre.
  Future<CheckoutSession> createBookSession(BookCheckoutRequest request);

  /// Ouvre une session de paiement unique pour un bundle.
  Future<CheckoutSession> createBundleSession(BundleCheckoutRequest request);
}

/// La passerelle de paiement d'un livre, quand la passerelle du serveur
/// sait en ouvrir une.
///
/// Le serveur peut tourner avec une passerelle d'abonnement seule : dans
/// ce cas, la vente d'un livre n'est pas servie, et la route le dit au
/// lieu d'échouer à l'intérieur du prestataire de paiement.
BookPaymentGateway? bookGatewayOf(PaymentGateway gateway) {
  final Object candidate = gateway;
  if (candidate is! BookPaymentGateway) return null;
  return candidate;
}

/// Une [PaymentGateway] qui parle à l'API Stripe en HTTP.
///
/// Le SDK Stripe publié sur pub.dev déclare `sdk: ">=2.12.0 <3.0.0"` et ne
/// peut pas être résolu sur le SDK Dart 3.12 que vise cette API : les deux
/// appels dont l'API a besoin sont donc émis directement contre l'API REST.
final class StripePaymentGateway implements PaymentGateway, BookPaymentGateway {
  /// Crée une passerelle.
  StripePaymentGateway({
    required this.secretKey,
    this.baseUrl = 'https://api.stripe.com/v1',
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  /// La clé secrète Stripe.
  final String secretKey;

  /// La racine de l'API Stripe.
  final String baseUrl;

  /// Le temps alloué à un appel à Stripe.
  final Duration timeout;

  final http.Client _client;

  @override
  Future<CheckoutSession> createSession(CheckoutRequest request) async {
    // Le port résout la commande lui-même : une passerelle de paiement
    // n'ouvre jamais une session pour la formule gratuite, ni pour un cycle
    // que la formule ne propose pas.
    final SubscriptionOrder order = SubscriptionOrder.resolve(
      planKey: request.plan.name,
      period: request.period,
    );
    final Map<String, String> body = <String, String>{
      'mode': 'subscription',
      'success_url': request.successUrl,
      'cancel_url': request.cancelUrl,
      'client_reference_id': request.userId,
      'metadata[user_id]': request.userId,
      'metadata[plan]': order.key,
      'line_items[0][quantity]': '1',
      'line_items[0][price_data][currency]': 'eur',
      'line_items[0][price_data][unit_amount]': '${order.priceInCents}',
      'line_items[0][price_data][recurring][interval]': order.stripeInterval,
      'line_items[0][price_data][recurring][interval_count]': '1',
      'line_items[0][price_data][product_data][name]':
          'Limpid ${order.displayName}',
      // Stripe ne recopie ni les métadonnées ni la référence client de la
      // session sur l'abonnement qu'il crée : le compte et la formule sont
      // donc écrits une seconde fois, sur l'abonnement, où le webhook de
      // paiement les lit.
      'subscription_data[metadata][user_id]': request.userId,
      'subscription_data[metadata][plan]': order.key,
      // L'essai n'est offert que si le compte ne l'a pas deja consomme :
      // la route qui commande lit l'historique du compte et decide.
      if (request.startTrial && order.trialDays > 0)
        'subscription_data[trial_period_days]': '${order.trialDays}',
    };

    final Map<String, String> headers = <String, String>{
      'authorization': 'Bearer $secretKey',
      'content-type': 'application/x-www-form-urlencoded',
      if (request.idempotencyKey != null)
        'idempotency-key': _stripeIdempotencyKey(request),
    };

    final http.Response response = await _client
        .post(
          Uri.parse('$baseUrl/checkout/sessions'),
          headers: headers,
          body: body,
        )
        .timeout(timeout);

    final Map<String, dynamic> payload = _decode(response);
    final Object? id = payload['id'];
    final Object? url = payload['url'];
    if (id is! String || url is! String) {
      throw const PaymentException(
        message:
            "Le service de paiement n'a pas renvoyé de session exploitable.",
      );
    }
    return CheckoutSession(
      id: id,
      url: url,
      ownerId: request.userId,
      status: payload['status'] is String
          ? payload['status']! as String
          : 'open',
    );
  }

  @override
  Future<CheckoutSession> createBookSession(BookCheckoutRequest request) async {
    // Le montant vient du livre : le serveur l'a lu dans sa base, et le
    // client ne peut pas le changer. La session est ouverte en mode
    // `payment` : un livre se paie une fois, il ne s'abonne pas.
    final Map<String, String> body = <String, String>{
      'mode': 'payment',
      'success_url': request.successUrl,
      'cancel_url': request.cancelUrl,
      'client_reference_id': request.userId,
      'metadata[user_id]': request.userId,
      'metadata[kind]': bookPaymentKind,
      'metadata[project_id]': request.projectId,
      // Le montant que le serveur a calcule — prix moins remise — est ecrit
      // dans la session : c'est lui que la ventilation doit reproduire,
      // meme si le rappel ne porte pas le montant encaisse.
      'metadata[amount_cents]': '${request.priceInCents}',
      if (request.promoCode != null) 'metadata[promo_code]': request.promoCode!,
      'line_items[0][quantity]': '1',
      'line_items[0][price_data][currency]': request.currency,
      'line_items[0][price_data][unit_amount]': '${request.priceInCents}',
      'line_items[0][price_data][product_data][name]': request.title,
    };

    final Map<String, String> headers = <String, String>{
      'authorization': 'Bearer $secretKey',
      'content-type': 'application/x-www-form-urlencoded',
      if (request.idempotencyKey != null)
        'idempotency-key': _bookIdempotencyKey(request),
    };

    final http.Response response = await _client
        .post(
          Uri.parse('$baseUrl/checkout/sessions'),
          headers: headers,
          body: body,
        )
        .timeout(timeout);

    final Map<String, dynamic> payload = _decode(response);
    final Object? id = payload['id'];
    final Object? url = payload['url'];
    if (id is! String || url is! String) {
      throw const PaymentException(
        message:
            "Le service de paiement n'a pas renvoyé de session exploitable.",
      );
    }
    return CheckoutSession(
      id: id,
      url: url,
      ownerId: request.userId,
      status: payload['status'] is String
          ? payload['status']! as String
          : 'open',
    );
  }

  @override
  Future<CheckoutSession> createBundleSession(
    BundleCheckoutRequest request,
  ) async {
    // Le montant vient du bundle : le serveur l'a lu dans sa base, et le
    // client ne peut pas le changer. La session est ouverte en mode
    // `payment` : un bundle se paie une fois, il ne s'abonne pas.
    final Map<String, String> body = <String, String>{
      'mode': 'payment',
      'success_url': request.successUrl,
      'cancel_url': request.cancelUrl,
      'client_reference_id': request.userId,
      'metadata[user_id]': request.userId,
      'metadata[kind]': bundlePaymentKind,
      'metadata[bundle_id]': request.bundleId,
      // Le montant que le serveur a calcule — prix moins remise — est ecrit
      // dans la session : c'est lui que la ventilation doit reproduire,
      // meme si le rappel ne porte pas le montant encaisse.
      'metadata[amount_cents]': '${request.priceInCents}',
      if (request.promoCode != null) 'metadata[promo_code]': request.promoCode!,
      'line_items[0][quantity]': '1',
      'line_items[0][price_data][currency]': request.currency,
      'line_items[0][price_data][unit_amount]': '${request.priceInCents}',
      'line_items[0][price_data][product_data][name]': request.title,
    };

    final Map<String, String> headers = <String, String>{
      'authorization': 'Bearer $secretKey',
      'content-type': 'application/x-www-form-urlencoded',
      if (request.idempotencyKey != null)
        'idempotency-key': _bundleIdempotencyKey(request),
    };

    final http.Response response = await _client
        .post(
          Uri.parse('$baseUrl/checkout/sessions'),
          headers: headers,
          body: body,
        )
        .timeout(timeout);

    final Map<String, dynamic> payload = _decode(response);
    final Object? id = payload['id'];
    final Object? url = payload['url'];
    if (id is! String || url is! String) {
      throw const PaymentException(
        message:
            "Le service de paiement n'a pas renvoyé de session exploitable.",
      );
    }
    return CheckoutSession(
      id: id,
      url: url,
      ownerId: request.userId,
      status: payload['status'] is String
          ? payload['status']! as String
          : 'open',
    );
  }

  @override
  Future<CheckoutSession?> retrieveSession(String sessionId) async {
    final http.Response response = await _client
        .get(
          Uri.parse('$baseUrl/checkout/sessions/$sessionId'),
          headers: <String, String>{'authorization': 'Bearer $secretKey'},
        )
        .timeout(timeout);
    if (response.statusCode == 404) return null;
    final Map<String, dynamic> payload = _decode(response);
    final Object? id = payload['id'];
    final Object? url = payload['url'];
    if (id is! String) return null;
    final String? ownerId = _ownerOf(payload);
    // Une session sans propriétaire est une session que le serveur ne peut
    // pas rattacher à un compte : elle n'est rendue à personne.
    if (ownerId == null) return null;
    return CheckoutSession(
      id: id,
      url: url is String ? url : '',
      ownerId: ownerId,
      status: payload['status'] is String
          ? payload['status']! as String
          : 'open',
    );
  }

  /// Le compte qui a ouvert la session, relu de Stripe.
  ///
  /// Le propriétaire est le `client_reference_id` de la session, complété
  /// par la métadonnée `user_id` quand la référence manque.
  static String? _ownerOf(Map<String, dynamic> payload) {
    final Object? reference = payload['client_reference_id'];
    if (reference is String && reference.isNotEmpty) return reference;
    final Object? metadata = payload['metadata'];
    if (metadata is Map<String, dynamic>) {
      final Object? userId = metadata['user_id'];
      if (userId is String && userId.isNotEmpty) return userId;
    }
    return null;
  }

  /// La clé d'idempotence envoyée à Stripe.
  ///
  /// Les clés de Stripe sont propres au marchand, pas au client : la clé
  /// est donc liée au compte qui a ouvert la session, pour que deux comptes
  /// qui utilisent la même clé ne partagent jamais une session.
  static String _stripeIdempotencyKey(CheckoutRequest request) {
    final String raw = '${request.userId}:${request.idempotencyKey}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// La clé d'idempotence envoyée à Stripe pour l'achat d'un livre.
  ///
  /// La clé est liée au compte **et** au livre : un même client qui
  /// commande deux livres différents ne confond jamais les deux sessions.
  static String _bookIdempotencyKey(BookCheckoutRequest request) {
    final String raw =
        '${request.userId}:${request.projectId}:${request.idempotencyKey}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// La clé d'idempotence envoyée à Stripe pour l'achat d'un bundle.
  ///
  /// La clé est liée au compte **et** au bundle : un même client qui
  /// commande deux bundles différents ne confond jamais les deux sessions.
  static String _bundleIdempotencyKey(BundleCheckoutRequest request) {
    final String raw =
        '${request.userId}:${request.bundleId}:${request.idempotencyKey}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PaymentException(
        message: 'Le service de paiement a refusé la demande.',
        details: <String, Object?>{'status': response.statusCode},
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const PaymentException(
        message: 'Le service de paiement a renvoyé une réponse invalide.',
      );
    }
    return decoded;
  }
}

/// Une [PaymentGateway] utilisée par la suite de tests.
final class StubPaymentGateway implements PaymentGateway, BookPaymentGateway {
  /// Crée une passerelle.
  StubPaymentGateway();

  final List<CheckoutRequest> requests = <CheckoutRequest>[];
  final List<BookCheckoutRequest> bookRequests = <BookCheckoutRequest>[];
  final List<BundleCheckoutRequest> bundleRequests = <BundleCheckoutRequest>[];
  final Map<String, CheckoutSession> _sessions = <String, CheckoutSession>{};

  /// L'erreur que la prochaine session leve, `null` quand tout va bien.
  ///
  /// Le double permet d'epreouver le chemin de l'echec : une commande dont
  /// la session ne s'ouvre pas doit rendre ce qu'elle avait reserve.
  Object? nextError;

  /// Leve l'erreur.preparee, s'il y en a une.
  void _throwPrepared() {
    final Object? error = nextError;
    if (error == null) return;
    nextError = null;
    throw error;
  }

  @override
  Future<CheckoutSession> createSession(CheckoutRequest request) async {
    requests.add(request);
    _throwPrepared();
    final CheckoutSession session = CheckoutSession(
      id: 'cs_test_${requests.length}',
      url: 'https://checkout.test/session/${requests.length}',
      ownerId: request.userId,
    );
    _sessions[session.id] = session;
    return session;
  }

  @override
  Future<CheckoutSession> createBookSession(BookCheckoutRequest request) async {
    bookRequests.add(request);
    _throwPrepared();
    final CheckoutSession session = CheckoutSession(
      id: 'cs_book_test_${bookRequests.length}',
      url: 'https://checkout.test/book/${bookRequests.length}',
      ownerId: request.userId,
    );
    _sessions[session.id] = session;
    return session;
  }

  @override
  Future<CheckoutSession> createBundleSession(
    BundleCheckoutRequest request,
  ) async {
    bundleRequests.add(request);
    _throwPrepared();
    final CheckoutSession session = CheckoutSession(
      id: 'cs_bundle_test_${bundleRequests.length}',
      url: 'https://checkout.test/bundle/${bundleRequests.length}',
      ownerId: request.userId,
    );
    _sessions[session.id] = session;
    return session;
  }

  @override
  Future<CheckoutSession?> retrieveSession(String sessionId) async {
    return _sessions[sessionId];
  }
}
