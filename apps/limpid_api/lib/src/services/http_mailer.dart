import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/app_exception.dart';
import 'mailer.dart';

/// Le nom de la variable d'environnement qui porte l'adresse du
/// fournisseur de courriel.
const String mailProviderUrlVariable = 'LIMPID_MAIL_PROVIDER_URL';

/// Le nom de la variable d'environnement qui porte le jeton du fournisseur
/// de courriel.
const String mailProviderTokenVariable = 'LIMPID_MAIL_PROVIDER_TOKEN';

/// Le délai d'attente de l'envoi, en secondes.
const int mailDeliveryTimeoutSeconds = 10;

/// Le port du courriel qui appelle un fournisseur HTTP.
///
/// L'adresse du fournisseur et son jeton viennent de l'environnement : ils
/// ne sont jamais écrits en dur. Le transport est injecté : la suite de
/// tests exerce le port sans compte, en lui donnant un client qui répond à
/// la place du fournisseur.
///
/// Le jeton du fournisseur ne sort jamais du corps de la demande
/// d'autorisation : il n'est ni écrit dans une URL, ni journalé, ni renvoyé
/// à l'auteur.
final class HttpMailer implements Mailer {
  /// Crée un port qui appelle le fournisseur [endpoint].
  ///
  /// [token] est le jeton d'autorisation du fournisseur : il ne sert qu'à
  /// l'authentifier. [client] est le transport ; il vaut le client HTTP par
  /// défaut.
  HttpMailer({
    required this.endpoint,
    required String token,
    http.Client? client,
    Duration? timeout,
  }) : // Le secret et le jeton sont privés. Un paramètre nommé ne peut pas
       // commencer par « _ » : la forme que le lint suggère
       // (`this._token`) est interdite par le langage.
       // ignore: prefer_initializing_formals
       _token = token,
       _client = client ?? http.Client(),
       _timeout =
           timeout ?? const Duration(seconds: mailDeliveryTimeoutSeconds);

  /// Crée un port depuis l'environnement.
  ///
  /// Lève une [ConfigException] quand une variable est présente mais
  /// malformée : une adresse de fournisseur doit être une URL absolue.
  factory HttpMailer.fromEnvironment(
    Map<String, String> environment, {
    http.Client? client,
  }) {
    final String url = _read(environment, mailProviderUrlVariable);
    final String token = _read(environment, mailProviderTokenVariable);
    return HttpMailer(endpoint: url, token: token, client: client);
  }

  /// L'adresse du fournisseur de courriel.
  final String endpoint;

  /// Le jeton d'autorisation du fournisseur.
  ///
  /// Le secret ne sert qu'à l'authentifier : il n'est jamais journalé et ne
  /// quitte jamais l'en-tête d'autorisation.
  final String _token;

  final http.Client _client;
  final Duration _timeout;

  @override
  bool get isConfigured => true;

  @override
  Future<void> sendTeamInvitation(TeamInvitationMail mail) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(endpoint),
            headers: <String, String>{
              'authorization': 'Bearer $_token',
              'content-type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(<String, Object?>{
              'to': mail.recipient,
              'subject': mail.subject,
              'text': mail.body,
            }),
          )
          .timeout(_timeout);
    } on http.ClientException {
      throw const ServiceUnavailableException(
        message: 'Le fournisseur de courriel n\'a pas pu être atteint.',
      );
    }

    if (response.statusCode >= 400) {
      throw ServiceUnavailableException(
        message: 'Le fournisseur de courriel a refusé l\'invitation.',
        details: <String, Object?>{'status': response.statusCode},
      );
    }
  }

  /// La valeur de la variable [name], lue dans l'environnement.
  static String _read(Map<String, String> environment, String name) {
    final String? raw = environment[name];
    final String value = raw == null ? '' : raw.trim();
    if (value.isEmpty) {
      throw ConfigException(
        variable: name,
        message: 'La variable d\'environnement $name est obligatoire.',
      );
    }
    return value;
  }
}

/// Le fournisseur de courriel de l'environnement, `null` quand aucun n'est
/// configuré.
///
/// L'absence des deux variables est le mode « aucun fournisseur » : le
/// message part dans le journal et le lien est rendu à l'auteur. Une
/// variable présente mais malformée est une erreur de configuration : elle
/// est signalée, jamais ignorée.
HttpMailer? mailerOfEnvironment(
  Map<String, String> environment, {
  http.Client? client,
}) {
  final String? url = environment[mailProviderUrlVariable];
  final String? token = environment[mailProviderTokenVariable];
  final bool hasUrl = url != null && url.trim().isNotEmpty;
  final bool hasToken = token != null && token.trim().isNotEmpty;
  if (!hasUrl && !hasToken) return null;
  if (!hasUrl || !hasToken) {
    final String missing = hasUrl
        ? mailProviderTokenVariable
        : mailProviderUrlVariable;
    throw ConfigException(
      variable: missing,
      message:
          'La variable d\'environnement $missing est obligatoire quand le '
          'fournisseur de courriel est configuré.',
    );
  }
  final Uri? parsed = Uri.tryParse(url.trim());
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    throw ConfigException(
      variable: mailProviderUrlVariable,
      message:
          'La variable d\'environnement $mailProviderUrlVariable doit être '
          'une URL absolue.',
    );
  }
  return HttpMailer(endpoint: url.trim(), token: token.trim(), client: client);
}
