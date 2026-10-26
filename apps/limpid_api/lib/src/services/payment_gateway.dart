import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../errors/app_exception.dart';

/// A Stripe checkout session.
final class CheckoutSession {
  /// Creates a session.
  const CheckoutSession({
    required this.id,
    required this.url,
    required this.ownerId,
    this.status = 'open',
  });

  /// The identifier of the session.
  final String id;

  /// The URL the buyer is redirected to.
  final String url;

  /// The account the session belongs to.
  ///
  /// The owner is read back with the session: a session is only ever handed
  /// to the account that opened it, and the URL of the checkout stays a
  /// secret of that account.
  final String ownerId;

  /// The status of the session.
  final String status;

  /// The JSON representation sent to the clients.
  Map<String, Object?> toJson() {
    return <String, Object?>{'session_id': id, 'url': url, 'status': status};
  }
}

/// A request of a checkout session.
final class CheckoutRequest {
  /// Creates a request.
  const CheckoutRequest({
    required this.userId,
    required this.plan,
    required this.successUrl,
    required this.cancelUrl,
    this.idempotencyKey,
  });

  /// The account buying the plan.
  final String userId;

  /// The identifier of the plan.
  final String plan;

  /// The URL the buyer lands on after a successful payment.
  final String successUrl;

  /// The URL the buyer lands on when the payment is abandoned.
  final String cancelUrl;

  /// The idempotency key of the call, when the client sent one.
  final String? idempotencyKey;
}

/// The payment capability of the API.
abstract interface class PaymentGateway {
  /// Opens a checkout session.
  Future<CheckoutSession> createSession(CheckoutRequest request);

  /// Reads back a checkout session, `null` when it does not exist.
  Future<CheckoutSession?> retrieveSession(String sessionId);
}

/// The prices of the plans, in cents.
const Map<String, int> planPrices = <String, int>{'studio': 1900, 'pro': 900};

/// A [PaymentGateway] talking to the Stripe API over HTTP.
///
/// The Stripe SDK published on pub.dev declares `sdk: ">=2.12.0 <3.0.0"` and
/// cannot be resolved on the Dart 3.12 SDK this API targets, so the two calls
/// the API needs are issued directly against the REST API.
final class StripePaymentGateway implements PaymentGateway {
  /// Creates a gateway.
  StripePaymentGateway({
    required this.secretKey,
    this.baseUrl = 'https://api.stripe.com/v1',
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  /// The Stripe secret key.
  final String secretKey;

  /// The root of the Stripe API.
  final String baseUrl;

  /// The time budget of a call to Stripe.
  final Duration timeout;

  final http.Client _client;

  @override
  Future<CheckoutSession> createSession(CheckoutRequest request) async {
    final int amount = planPrices[request.plan] ?? planPrices['studio']!;
    final Map<String, String> body = <String, String>{
      'mode': 'payment',
      'success_url': request.successUrl,
      'cancel_url': request.cancelUrl,
      'client_reference_id': request.userId,
      'metadata[user_id]': request.userId,
      'metadata[plan]': request.plan,
      'line_items[0][quantity]': '1',
      'line_items[0][price_data][currency]': 'eur',
      'line_items[0][price_data][unit_amount]': '$amount',
      'line_items[0][price_data][product_data][name]': 'Limpid ${request.plan}',
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

  /// The account that opened the session read back from Stripe.
  ///
  /// The owner is the `client_reference_id` of the session, completed by the
  /// `user_id` metadata when the reference is missing.
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

  /// The idempotency key sent to Stripe.
  ///
  /// The keys of Stripe are scoped to the merchant, not to the client: the
  /// key is therefore bound to the account that opened the session, so two
  /// accounts using the same key never share a session.
  static String _stripeIdempotencyKey(CheckoutRequest request) {
    final String raw = '${request.userId}:${request.idempotencyKey}';
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

/// A [PaymentGateway] used by the test suite.
final class StubPaymentGateway implements PaymentGateway {
  /// Creates a gateway.
  StubPaymentGateway();

  final List<CheckoutRequest> requests = <CheckoutRequest>[];
  final Map<String, CheckoutSession> _sessions = <String, CheckoutSession>{};

  @override
  Future<CheckoutSession> createSession(CheckoutRequest request) async {
    requests.add(request);
    final CheckoutSession session = CheckoutSession(
      id: 'cs_test_${requests.length}',
      url: 'https://checkout.test/session/${requests.length}',
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
