import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'kdp_amazon_refusal.dart';
import 'kdp_gateway.dart';

/// La passerelle de dépôt auprès d'Amazon KDP.
///
/// La passerelle parle à Amazon par HTTPS : elle obtient un jeton d'accès
/// auprès du service d'autorisation d'Amazon, le renouvelle quand il
/// expire, puis remet le dossier préparé.
///
/// **Le contrat d'Amazon ne porte pas de clé d'idempotence.** Amazon
/// accepte un dossier par soumission : renvoyer deux fois le même dossier
/// crée deux fiches KDP, donc deux ASIN pour un seul livre. La passerelle
/// n'envoie donc aucun en-tête `idempotency-key` — Amazon l'ignorerait —
/// et c'est la trace locale du dépôt qui empêche le second envoi.
///
/// La chaîne d'appels partage **une seule échéance**, tirée du budget de la
/// requête HTTP : chaque appel reçoit le temps qui reste et n'est pas
/// envoyé quand il n'y en a plus. Une chaîne ne peut donc pas dépasser le
/// budget de la requête.
///
/// Quand le dossier est parti et qu'Amazon n'a pas répondu, la passerelle
/// rend un [KdpSubmissionUnknown] : elle ne sait pas si Amazon a reçu le
/// dossier, et le dossier ne repartira pas tout seul.
///
/// Le jeton d'accès ne sort jamais de l'en-tête d'autorisation : il n'est
/// écrit ni dans une URL, ni dans un journal, ni dans la trace du dépôt.
/// Les adresses d'Amazon sont fixées par le code : une URL venue de
/// l'appelant n'est jamais suivie.
///
/// Le transport est injecté : la suite de tests exerce la passerelle sans
/// compte KDP, en lui donnant un client qui répond à la place d'Amazon.
final class AmazonKdpGateway implements KdpGateway {
  /// Crée une passerelle.
  ///
  /// [client] est le transport utilisé pour parler à Amazon ; il vaut le
  /// client HTTP par défaut. [budget] est le temps que la chaîne d'appels
  /// peut prendre : il vient de la requête, jamais d'un délai par appel.
  /// [clock] rend l'heure injectable : les tests font passer le temps sans
  /// attendre.
  AmazonKdpGateway({
    required this.clientId,
    required String clientSecret,
    required String refreshToken,
    required this.budget,
    http.Client? client,
    DateTime Function()? clock,
  }) : // Le secret et le jeton de renouvellement sont privés. Un paramètre
       // nommé ne peut pas commencer par « _ » : la forme que le lint
       // suggère (`this._clientSecret`) est interdite par le langage.
       // ignore: prefer_initializing_formals
       _clientSecret = clientSecret,
       // ignore: prefer_initializing_formals
       _refreshToken = refreshToken,
       _client = client ?? http.Client(),
       _clock = clock ?? _utcNow;

  /// L'adresse du service d'autorisation d'Amazon.
  ///
  /// L'adresse est fixe : elle ne vient jamais de l'appelant.
  static const String tokenUrl = 'https://api.amazon.com/auth/o2/token';

  /// L'adresse de dépôt d'Amazon KDP.
  ///
  /// L'adresse est fixe : elle ne vient jamais de l'appelant.
  static const String depositUrl = 'https://api.kdp.amazon.com/v1/submissions';

  /// La durée de validité d'un jeton, quand Amazon n'en annonce pas.
  static const int defaultTokenLifetimeSeconds = 3600;

  /// La durée de vie minimale retenue pour un jeton d'accès.
  ///
  /// Amazon annonce parfois une durée très courte : sans cette borne, le
  /// jeton serait déjà expiré au moment du calcul et chaque dépôt
  /// redemanderait un jeton à Amazon.
  static const int minTokenLifetimeSeconds = 600;

  /// La marge retenue avant l'expiration annoncée du jeton.
  ///
  /// Le jeton est renouvelé un peu avant son terme : un appel ne part
  /// jamais avec un jeton qui expire au milieu du voyage.
  static const Duration tokenLifetimeMargin = Duration(seconds: 60);

  /// Les statuts par lesquels Amazon refuse un dossier.
  ///
  /// Les autres statuts ont chacun leur motif : un jeton refusé, un
  /// compte bloqué, un dépôt bridé ou une panne d'Amazon ne se relancent
  /// pas de la même façon.
  static const Set<int> refusalStatuses = <int>{400, 409, 422};

  /// L'identifiant du client de l'intégration.
  final String clientId;

  /// Le temps que la chaîne d'appels peut prendre.
  ///
  /// Le budget vient de la requête HTTP : il est partagé par tous les
  /// appels de la chaîne, jamais dépassé par elle.
  final Duration budget;

  /// Le secret du client de l'intégration.
  ///
  /// Le secret ne sert qu'à l'obtention du jeton : il n'est jamais
  /// journalé, ne quitte jamais le corps de la demande d'autorisation et
  /// n'est pas lisible depuis l'extérieur de la passerelle.
  final String _clientSecret;

  /// Le jeton de renouvellement de l'intégration.
  ///
  /// C'est la seule credential qui n'expire pas : le jeton d'accès en est
  /// dérivé. Elle n'est pas lisible depuis l'extérieur de la passerelle.
  final String _refreshToken;

  final http.Client _client;
  final DateTime Function() _clock;

  String? _token;
  DateTime? _tokenExpiry;

  static DateTime _utcNow() => DateTime.now().toUtc();

  @override
  Future<KdpSubmissionOutcome> submit(KdpSubmissionRequest request) async {
    final KdpCallBudget callBudget = KdpCallBudget(
      budget: budget,
      now: _clock(),
    );
    try {
      String token = await _accessToken(callBudget);
      http.Response response = await _post(token, request, callBudget);
      if (response.statusCode == HttpStatus.unauthorized) {
        // Amazon refuse le jeton : il est renouvelé et l'appel est
        // réessayé une seule fois. Amazon a refusé la première demande,
        // il n'a donc créé aucune soumission : le réessai est sans risque.
        _forgetToken();
        token = await _accessToken(callBudget);
        response = await _post(token, request, callBudget);
      }
      return _verdict(response);
    } on _AmazonCallFailed catch (failure) {
      return failure.isOutcomeUnknown
          ? KdpSubmissionUnknown(failure.reason)
          : KdpSubmissionUnavailable(failure.reason);
    }
  }

  /// Le jeton d'accès, renouvelé quand il est expiré.
  Future<String> _accessToken(KdpCallBudget callBudget) async {
    final String? cached = _token;
    final DateTime? expiry = _tokenExpiry;
    if (cached != null && expiry != null && expiry.isAfter(_clock())) {
      return cached;
    }
    return _renewToken(callBudget);
  }

  /// Demande un jeton d'accès à Amazon et le garde en mémoire.
  ///
  /// Le jeton est demandé par le corps de la demande : il ne figure ni dans
  /// l'adresse, ni dans un en-tête qui pourrait être journalisé.
  Future<String> _renewToken(KdpCallBudget callBudget) async {
    final Duration remaining = callBudget.remainingAt(_clock());
    if (remaining <= Duration.zero) {
      throw const _AmazonCallFailed(KdpDepositFailures.budgetExhausted);
    }
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(tokenUrl),
            headers: <String, String>{
              'content-type': 'application/x-www-form-urlencoded',
            },
            body: <String, String>{
              'grant_type': 'refresh_token',
              'refresh_token': _refreshToken,
              'client_id': clientId,
              'client_secret': _clientSecret,
            },
          )
          .timeout(remaining);
    } on TimeoutException {
      throw const _AmazonCallFailed(KdpDepositFailures.tokenTimeout);
    } on http.ClientException {
      throw const _AmazonCallFailed(KdpDepositFailures.tokenUnreachable);
    } on IOException {
      // La connexion a été coupée, la négociation TLS a échoué : le jeton
      // n'a pas pu être obtenu, le dossier n'est pas parti.
      throw const _AmazonCallFailed(KdpDepositFailures.tokenUnreachable);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _AmazonCallFailed(_authorizationReasonOf(response.statusCode));
    }

    final Map<String, dynamic> payload;
    try {
      payload = _decodeObject(_bodyOf(response));
    } on FormatException {
      throw const _AmazonCallFailed(KdpDepositFailures.tokenUnreadable);
    }
    final Object? token = payload['access_token'];
    if (token is! String || token.isEmpty) {
      throw const _AmazonCallFailed(KdpDepositFailures.tokenUnreadable);
    }

    final int lifetime = _lifetimeOf(payload['expires_in']);
    _token = token;
    _tokenExpiry = _clock()
        .add(Duration(seconds: lifetime))
        .subtract(tokenLifetimeMargin);
    return token;
  }

  /// Remet le dépôt à Amazon.
  ///
  /// Le jeton d'accès ne voyage que dans l'en-tête d'autorisation : il ne
  /// figure jamais dans l'adresse, qui est celle d'Amazon. Aucun en-tête
  /// d'idempotence n'est envoyé : le contrat d'Amazon n'en porte pas, et
  /// un en-tête ignoré laisserait croire à une protection qui n'existe pas.
  Future<http.Response> _post(
    String token,
    KdpSubmissionRequest request,
    KdpCallBudget callBudget,
  ) async {
    final Duration remaining = callBudget.remainingAt(_clock());
    if (remaining <= Duration.zero) {
      throw const _AmazonCallFailed(KdpDepositFailures.budgetExhausted);
    }
    try {
      return await _client
          .post(
            Uri.parse(depositUrl),
            headers: <String, String>{
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode(_payload(request)),
          )
          .timeout(remaining);
    } on TimeoutException {
      // Le dossier est parti : Amazon l'a peut-être reçu.
      throw const _AmazonCallFailed(
        KdpDepositFailures.unknownTimeout,
        isOutcomeUnknown: true,
      );
    } on http.ClientException {
      throw const _AmazonCallFailed(
        KdpDepositFailures.unknownUnreachable,
        isOutcomeUnknown: true,
      );
    } on IOException {
      // La connexion a été coupée ou la négociation TLS a échoué : le
      // dossier est peut-être parti.
      throw const _AmazonCallFailed(
        KdpDepositFailures.unknownUnreachable,
        isOutcomeUnknown: true,
      );
    }
  }

  /// Le corps de la demande de dépôt.
  ///
  /// Le corps porte les métadonnées de la fiche produit et l'adresse des
  /// deux fichiers déposés.
  Map<String, Object?> _payload(KdpSubmissionRequest request) {
    return <String, Object?>{
      'metadata': <String, Object?>{
        'title': request.title,
        'author': request.author,
        'description': request.description,
        'keywords': List<String>.unmodifiable(request.keywords),
        'categories': List<String>.unmodifiable(request.categories),
        'isbn': request.isbn,
        'language': request.language,
        'publisher': request.publisher,
      },
      'files': <String, Object?>{
        'epub': <String, Object?>{'url': request.epubUrl},
        'pdf': <String, Object?>{'url': request.pdfUrl},
      },
    };
  }

  /// Le verdict d'Amazon, lu de sa réponse.
  ///
  /// Une erreur d'Amazon après l'envoi du dossier ne prouve pas que le
  /// dossier a été refusé : il a pu être enregistré avant que la réponse
  /// ne se perde. Seuls les statuts qui prouvent le refus — un jeton
  /// refusé, un compte bloqué, un dépôt bridé, un dossier refusé — sont
  /// rendus comme des échecs que l'auteur peut corriger.
  KdpSubmissionOutcome _verdict(http.Response response) {
    final int status = response.statusCode;
    final String body = _bodyOf(response);
    if (status >= 200 && status < 300) {
      final String? submissionId;
      try {
        submissionId = _submissionIdOf(body);
      } on FormatException {
        // Amazon a traité la demande, mais sa réponse est illisible : la
        // soumission existe peut-être déjà, son identifiant est perdu.
        return const KdpSubmissionUnknown(KdpDepositFailures.unknownUnreadable);
      }
      if (submissionId == null) {
        return const KdpSubmissionUnknown(KdpDepositFailures.unknownUnreadable);
      }
      return KdpSubmissionAccepted(submissionId);
    }
    if (refusalStatuses.contains(status)) {
      return KdpSubmissionRefused(KdpAmazonRefusal.read(body));
    }
    if (status == HttpStatus.unauthorized) {
      return const KdpSubmissionUnavailable(KdpDepositFailures.unauthorized);
    }
    if (status == HttpStatus.forbidden) {
      return const KdpSubmissionUnavailable(KdpDepositFailures.accountBlocked);
    }
    if (status == HttpStatus.tooManyRequests) {
      return const KdpSubmissionUnavailable(KdpDepositFailures.rateLimited);
    }
    if (status == HttpStatus.requestTimeout || status >= 500) {
      // Amazon a reçu la demande et n'a pas su la traiter : la soumission
      // existe peut-être déjà.
      return const KdpSubmissionUnknown(KdpDepositFailures.unknownServerError);
    }
    return const KdpSubmissionUnavailable(KdpDepositFailures.serverError);
  }

  /// Le corps de la réponse, vide quand Amazon n'envoie pas du texte.
  ///
  /// Le corps est décodé strictement : une réponse qui n'est pas de
  /// l'UTF-8 ne doit pas faire tomber l'appel, elle doit être traitée
  /// comme une réponse illisible.
  String _bodyOf(http.Response response) {
    try {
      return response.body;
    } on FormatException {
      return '';
    }
  }

  /// Le motif d'un refus d'autorisation, selon le statut du service
  /// d'autorisation d'Amazon.
  static String _authorizationReasonOf(int status) {
    if (status == HttpStatus.unauthorized) {
      return KdpDepositFailures.unauthorized;
    }
    if (status == HttpStatus.forbidden) {
      return KdpDepositFailures.accountBlocked;
    }
    if (status == HttpStatus.tooManyRequests) {
      return KdpDepositFailures.rateLimited;
    }
    return KdpDepositFailures.serverError;
  }

  /// L'identifiant du dépôt chez Amazon, `null` quand la réponse ne le
  /// porte pas.
  String? _submissionIdOf(String body) {
    final Map<String, dynamic> payload = _decodeObject(body);
    for (final String key in <String>['submission_id', 'submissionId', 'id']) {
      final Object? value = payload[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  /// La durée de validité annoncée par Amazon.
  ///
  /// La durée annoncée est ramenée à la durée minimale : un jeton trop
  /// court serait déjà expiré au moment du calcul, et chaque dépôt
  /// redemanderait un jeton à Amazon.
  int _lifetimeOf(Object? raw) {
    int announced = defaultTokenLifetimeSeconds;
    if (raw is int && raw > 0) {
      announced = raw;
    } else if (raw is num && raw > 0) {
      announced = raw.toInt();
    }
    if (announced < minTokenLifetimeSeconds) return minTokenLifetimeSeconds;
    return announced;
  }

  /// Le corps JSON de la réponse, un objet vide quand il est illisible.
  Map<String, dynamic> _decodeObject(String body) {
    if (body.trim().isEmpty) return const <String, dynamic>{};
    final Object? decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Expected a JSON object.');
  }

  /// Oublie le jeton d'accès : le prochain appel en demande un nouveau.
  void _forgetToken() {
    _token = null;
    _tokenExpiry = null;
  }
}

/// L'appel à Amazon a échoué sans réponse.
///
/// L'exception porte le motif de l'échec et dit si l'issue du dépôt est
/// incertaine : un dossier parti dont Amazon n'a pas répondu ne peut pas
/// être relancé comme un échec ordinaire.
final class _AmazonCallFailed implements Exception {
  /// Crée l'échec.
  const _AmazonCallFailed(this.reason, {this.isOutcomeUnknown = false});

  /// Le motif de l'échec, écrit pour l'auteur.
  final String reason;

  /// Vrai quand le dossier est parti et que l'issue n'est pas connue.
  final bool isOutcomeUnknown;
}
