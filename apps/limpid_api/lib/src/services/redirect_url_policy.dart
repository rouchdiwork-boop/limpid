import '../errors/app_exception.dart';

/// La longueur maximale d'une adresse de retour.
const int maxRedirectUrlLength = 2048;

/// Les schémas acceptés pour une adresse de retour.
///
/// `http` n'est accepté que pour la boucle locale : en production, le
/// retour de l'acheteur traverse Internet.
const Set<String> allowedRedirectSchemes = <String>{'https', 'http'};

/// Valide l'adresse de retour [raw] et renvoie sa forme normalisée.
///
/// L'adresse de retour est une **surface d'hameçonnage** : le serveur la
/// transmet au prestataire de paiement, qui y renvoie l'acheteur une fois
/// le paiement fait. Une adresse choisie par l'appelant — et non par le
/// serveur — ferait porter par un site tiers l'identifiant de session et
/// la confiance de la plateforme.
///
/// La règle est donc une **liste blanche** : l'adresse doit viser une des
/// origines autorisées de la plateforme, celles que l'application sert
/// (`CORS_ALLOWED_ORIGINS`). Le client ne choisit donc pas sa destination :
/// il choisit un **écran** de la plateforme, et le serveur refuse toute
/// adresse qui en sort.
///
/// [allowedOrigins] peut être vide : c'est le cas d'un poste de
/// développement qui n'a pas configuré les origines. La boucle locale
/// reste alors acceptée, et elle seule.
String validateRedirectUrl(String raw, {required List<String> allowedOrigins}) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const ValidationException(
      field: 'url',
      message: 'L\'adresse de retour est obligatoire.',
    );
  }
  if (trimmed.length > maxRedirectUrlLength) {
    throw ValidationException(
      field: 'url',
      message:
          'L\'adresse de retour ne peut pas dépasser '
          '$maxRedirectUrlLength caractères.',
    );
  }

  final Uri? parsed = Uri.tryParse(trimmed);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    throw const ValidationException(
      field: 'url',
      message:
          'L\'adresse de retour doit être une URL absolue, avec un schéma '
          'et un hôte.',
    );
  }

  final String scheme = parsed.scheme.toLowerCase();
  if (!allowedRedirectSchemes.contains(scheme)) {
    throw const ValidationException(
      field: 'url',
      message: 'L\'adresse de retour doit être en https.',
    );
  }
  if (parsed.userInfo.isNotEmpty) {
    throw const ValidationException(
      field: 'url',
      message: 'L\'adresse de retour ne doit pas porter d\'identifiants.',
    );
  }

  final bool loopback = isLoopbackHost(parsed.host);
  if (scheme != 'https' && !loopback) {
    throw const ValidationException(
      field: 'url',
      message: 'L\'adresse de retour doit être en https.',
    );
  }

  if (!_isAllowedOrigin(parsed, allowedOrigins, loopback)) {
    throw const ValidationException(
      field: 'url',
      message:
          'L\'adresse de retour doit viser une origine autorisée de la '
          'plateforme.',
    );
  }
  return parsed.toString();
}

/// Indique si l'origine de [url] est autorisée.
///
/// Une origine autorisée est une origine de la liste. La liste vide n'autorise
/// que la boucle locale : un poste de développement qui n'a pas configuré les
/// origines ne peut donc pas être renvoyé vers un site tiers.
bool _isAllowedOrigin(Uri url, List<String> allowedOrigins, bool loopback) {
  final String origin = _originOf(url);
  for (final String allowed in allowedOrigins) {
    final Uri? parsed = Uri.tryParse(allowed.trim());
    // Une origine malformee dans l'environnement ne vaut rien : elle
    // n'autorise rien, et elle ne fait pas tomber le serveur.
    if (parsed == null) continue;
    if (_originOf(parsed) == origin) return true;
  }
  return loopback && allowedOrigins.isEmpty;
}

/// L'origine d'une URL : schéma, hôte et port.
///
/// Le port par défaut n'est pas écrit : `https://app.test` et
/// `https://app.test:443` sont la même origine.
String _originOf(Uri url) {
  final int? port = url.hasPort ? url.port : null;
  final bool defaultPort =
      (url.scheme == 'https' && port == 443) ||
      (url.scheme == 'http' && port == 80);
  return '${url.scheme}://${url.host.toLowerCase()}'
      '${port != null && !defaultPort ? ':$port' : ''}';
}

/// Indique si [host] est la boucle locale.
///
/// Le nom `localhost` et les adresses de la boucle sont reconnus ; le reste
/// n'est pas deviné.
bool isLoopbackHost(String host) {
  final String value = host.trim().toLowerCase();
  if (value == 'localhost' || value == '::1' || value == '[::1]') return true;
  return value == '127.0.0.1' || value.startsWith('127.');
}
