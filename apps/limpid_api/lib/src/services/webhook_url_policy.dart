import '../errors/app_exception.dart';

/// La longueur maximale d'une URL de rappel.
const int maxCallbackUrlLength = 2048;

/// Les schémas acceptés pour une URL de rappel.
///
/// `http` n'est accepté qu'en développement : en production, le rappel
/// traverse Internet et le compte peut y écrire des données.
const Set<String> allowedCallbackSchemes = <String>{'https', 'http'};

/// Valide l'URL de rappel [raw] et renvoie sa forme normalisée.
///
/// Une URL de rappel est une surface d'éjection de données : le serveur y
/// écrit la charge de l'événement. Elle doit donc être absolue, en `https`,
/// et viser un hôte public.
///
/// [allowInsecure] assouplit deux règles : le schéma `http` et les hôtes
/// privés. Il est vrai seulement dans le profil de développement, où l'on
/// teste la livraison contre un rappel local. En production, les deux
/// règles s'appliquent.
String validateCallbackUrl(String raw, {required bool allowInsecure}) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const ValidationException(
      field: 'url',
      message: 'L\'URL de rappel est obligatoire.',
    );
  }
  if (trimmed.length > maxCallbackUrlLength) {
    throw ValidationException(
      field: 'url',
      message:
          'L\'URL de rappel ne peut pas dépasser '
          '$maxCallbackUrlLength caractères.',
    );
  }

  final Uri? parsed = Uri.tryParse(trimmed);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    throw const ValidationException(
      field: 'url',
      message:
          'L\'URL de rappel doit être une URL absolue, avec un schéma et '
          'un hôte.',
    );
  }

  final String scheme = parsed.scheme.toLowerCase();
  if (!allowedCallbackSchemes.contains(scheme)) {
    throw const ValidationException(
      field: 'url',
      message: 'L\'URL de rappel doit être en https.',
    );
  }
  if (scheme != 'https' && !allowInsecure) {
    throw const ValidationException(
      field: 'url',
      message: 'L\'URL de rappel doit être en https.',
    );
  }
  if (parsed.userInfo.isNotEmpty) {
    throw const ValidationException(
      field: 'url',
      message: 'L\'URL de rappel ne doit pas porter d\'identifiants.',
    );
  }
  if (!allowInsecure && isPrivateHost(parsed.host)) {
    throw const ValidationException(
      field: 'url',
      message:
          'L\'URL de rappel doit viser un hôte public : les adresses '
          'privées et locales sont refusées.',
    );
  }
  return parsed.toString();
}

/// Indique si [host] désigne un hôte privé, local ou réservé.
///
/// Le serveur écrit dans l'URL de rappel : viser la boucle locale ou le
/// réseau interne du déploiement transformerait le rappel en vecteur
/// d'ejection de données vers l'infrastructure.
bool isPrivateHost(String host) {
  final String lowered = host.trim().toLowerCase();
  if (lowered.isEmpty) return true;
  if (lowered == 'localhost' || lowered.endsWith('.localhost')) return true;
  if (lowered.endsWith('.local') || lowered.endsWith('.internal')) return true;

  final List<int>? octets = _ipv4Octets(lowered);
  if (octets != null) return _isPrivateIpv4(octets);

  if (lowered.contains(':')) return _isPrivateIpv6(lowered);
  return false;
}

/// Les quatre octets d'une adresse IPv4, `null` quand [host] n'en est pas une.
List<int>? _ipv4Octets(String host) {
  final List<String> parts = host.split('.');
  if (parts.length != 4) return null;
  final List<int> octets = <int>[];
  for (final String part in parts) {
    if (part.isEmpty || part.length > 3) return null;
    final int? value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return null;
    octets.add(value);
  }
  return octets;
}

/// Indique si les octets [octets] désignent une adresse privée.
bool _isPrivateIpv4(List<int> octets) {
  if (octets[0] == 0 || octets[0] == 10 || octets[0] == 127) return true;
  if (octets[0] == 169 && octets[1] == 254) return true;
  if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
  if (octets[0] == 192 && octets[1] == 168) return true;
  if (octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127) return true;
  return false;
}

/// Indique si [address] désigne une adresse IPv6 privée ou locale.
bool _isPrivateIpv6(String address) {
  if (address == '::1' || address == '::') return true;
  if (address.startsWith('fc') || address.startsWith('fd')) return true;
  if (address.startsWith('fe80')) return true;
  return false;
}
