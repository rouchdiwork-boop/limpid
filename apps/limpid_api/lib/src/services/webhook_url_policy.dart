import 'dart:async';
import 'dart:io';

import '../errors/app_exception.dart';

/// La longueur maximale d'une URL de rappel.
const int maxCallbackUrlLength = 2048;

/// Les schémas acceptés pour une URL de rappel.
///
/// `http` n'est accepté qu'en développement : en production, le rappel
/// traverse Internet et le compte peut y écrire des données.
const Set<String> allowedCallbackSchemes = <String>{'https', 'http'};

/// Le nombre maximal de parties d'une adresse IPv4.
const int _maxIpv4Parts = 4;

/// Le temps accordé à la résolution d'un nom de rappel.
///
/// La résolution est faite avant chaque livraison : un résolveur lent ne
/// doit pas retarder l'envoi plus que le délai du point de rappel.
const Duration hostResolutionTimeout = Duration(seconds: 2);

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
///
/// L'analyse porte sur le **texte** de l'hôte, et elle couvre toutes les
/// notations d'une adresse IPv4 : `127.0.0.1`, `127.1`, `2130706433`,
/// `0x7f.0.0.1`, `0177.0.0.1`. Une adresse IPv4 cartographiée en IPv6
/// (`::ffff:127.0.0.1`) est traitée comme l'IPv4 qu'elle porte.
///
/// Un nom de domaine n'est pas judge ici : il est juge a la livraison, une
/// fois resolu — voir [resolvesToPrivateHost].
bool isPrivateHost(String host) {
  final String lowered = _normalizedHost(host);
  if (lowered.isEmpty) return true;
  if (lowered == 'localhost' || lowered.endsWith('.localhost')) return true;
  if (lowered.endsWith('.local') || lowered.endsWith('.internal')) return true;

  final List<int>? octets = _ipv4Octets(lowered);
  if (octets != null) return _isPrivateIpv4(octets);

  if (lowered.contains(':')) return _isPrivateIpv6(lowered);
  return false;
}

/// Le verdict de la resolution d'un nom de rappel.
enum HostResolution {
  /// Le nom se resout vers une adresse publique : le rappel est accepte.
  public,

  /// Le nom se resout vers une adresse du reseau interne : le rappel est
  /// refuse, car il deviendrait une ejection vers l'infrastructure.
  privateAddress,

  /// Le nom ne se resout pas, ou le resolveur ne repond pas : le rappel
  /// est refuse plutot que d'ecrire dans le vide.
  unresolved,
}

/// Resout le nom [host] et dit ce que le rappel vaut.
///
/// Un nom public peut designer une adresse interne : `127.0.0.1.nip.io`
/// vaut `127.0.0.1`, et un enregistrement peut changer entre la
/// declaration du rappel et la livraison. La resolution est donc refaite
/// au moment d'ecrire, et chaque adresse obtenue est jugee.
Future<HostResolution> resolveHost(String host) async {
  final String normalized = _normalizedHost(host);
  if (normalized.isEmpty) return HostResolution.unresolved;
  // Une adresse deja ecrite en clair est jugee sans resolution.
  if (_ipv4Octets(normalized) != null || normalized.contains(':')) {
    return isPrivateHost(normalized)
        ? HostResolution.privateAddress
        : HostResolution.public;
  }
  try {
    final List<InternetAddress> addresses = await InternetAddress.lookup(
      normalized,
    ).timeout(hostResolutionTimeout);
    if (addresses.isEmpty) return HostResolution.unresolved;
    return addresses.any(_isPrivateAddress)
        ? HostResolution.privateAddress
        : HostResolution.public;
  } on SocketException {
    return HostResolution.unresolved;
  } on TimeoutException {
    // Un resoluteur lent ne doit pas retenir la livraison : le rappel est
    // refuse, et le refus est dit.
    return HostResolution.unresolved;
  } on Object {
    // Une resolution qui echoue ne doit jamais autoriser l'ecriture.
    return HostResolution.unresolved;
  }
}

/// Indique si le nom [host] se resout vers une adresse privee.
Future<bool> resolvesToPrivateHost(String host) async =>
    await resolveHost(host) != HostResolution.public;

/// L'hôte normalisé : minuscules, sans crochets, sans point final.
///
/// `Uri.host` garde les crochets d'une adresse IPv6 litterale ; la
/// comparaison doit porter sur la forme nue.
String _normalizedHost(String host) {
  String value = host.trim().toLowerCase();
  if (value.startsWith('[') && value.endsWith(']')) {
    value = value.substring(1, value.length - 1);
  }
  while (value.endsWith('.')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/// Les quatre octets d'une adresse IPv4, `null` quand [host] n'en est pas une.
///
/// Toutes les notations sont acceptees : chacune des parties peut etre
/// decimale, hexadecimale (`0x7f`) ou octale (`0177`), et la derniere
/// partie peut couvrir plusieurs octets (`127.1`, `2130706433`). C'est la
/// lecture que fait `inet_aton`, et c'est celle que ferait le resolution
/// DNS.
List<int>? _ipv4Octets(String host) {
  final List<String> parts = host.split('.');
  if (parts.isEmpty || parts.length > _maxIpv4Parts) return null;

  final List<int> values = <int>[];
  for (int index = 0; index < parts.length; index++) {
    final int? value = _ipPartOf(parts[index]);
    if (value == null) return null;
    values.add(value);
  }

  // La derniere partie couvre les octets qui restent : `127.1` vaut
  // `127.0.0.1`, et `2130706433` vaut `127.0.0.1` aussi.
  final int last = values.removeLast();
  final int remainingBits = (4 - values.length) * 8;
  if (remainingBits == 0) {
    if (last > 255) return null;
  } else {
    final int maximum = (1 << remainingBits) - 1;
    if (last > maximum) return null;
  }
  values.add(last >> (remainingBits - 8));
  for (int shift = 8; shift < remainingBits; shift += 8) {
    values.add((last >> (remainingBits - shift - 8)) & 0xff);
  }
  while (values.length < 4) {
    values.insert(0, 0);
  }
  return values;
}

/// La valeur d'une partie d'adresse IPv4, `null` quand elle n'en est pas une.
///
/// La partie est decimale, hexadecimale (`0x7f`) ou octale (`0177`), et
/// elle ne peut pas depasser la place qu'elle occupe.
int? _ipPartOf(String part) {
  if (part.isEmpty || part.length > 10) return null;

  int base = 10;
  String digits = part;
  if (digits.startsWith('0x') || digits.startsWith('0X')) {
    base = 16;
    digits = digits.substring(2);
  } else if (digits.length > 1 && digits.startsWith('0')) {
    base = 8;
    digits = digits.substring(1);
  }
  if (digits.isEmpty) return 0;
  final int? value = int.tryParse(digits, radix: base);
  if (value == null || value < 0) return null;
  return value;
}

/// Indique si les octets [octets] désignent une adresse privée.
bool _isPrivateIpv4(List<int> octets) {
  if (octets[0] == 0 || octets[0] == 10 || octets[0] == 127) return true;
  if (octets[0] == 169 && octets[1] == 254) return true;
  if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
  if (octets[0] == 192 && octets[1] == 168) return true;
  if (octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127) return true;
  // Les adresses reservees ne sont pas publiques non plus.
  if (octets[0] >= 224) return true;
  return false;
}

/// Indique si [address] désigne une adresse IPv6 privée ou locale.
bool _isPrivateIpv6(String address) {
  final String value = address.toLowerCase();
  if (value == '::1' || value == '::') return true;
  if (value.startsWith('fc') || value.startsWith('fd')) return true;
  if (value.startsWith('fe80')) return true;

  // Une adresse IPv4 cartographiee porte l'IPv4 dans ses derniers bits :
  // `::ffff:127.0.0.1` est la boucle locale.
  if (value.startsWith('::ffff:')) {
    final String mapped = value.substring('::ffff:'.length);
    final List<int>? octets = _ipv4Octets(mapped);
    if (octets != null) return _isPrivateIpv4(octets);
    // La forme hexadecimale : `::ffff:7f00:1`.
    final List<String> groups = value.split(':');
    if (groups.length >= 2) {
      final int? high = int.tryParse(groups[groups.length - 2], radix: 16);
      final int? low = int.tryParse(groups[groups.length - 1], radix: 16);
      if (high != null && low != null) {
        return _isPrivateIpv4(<int>[
          high >> 8,
          high & 0xff,
          low >> 8,
          low & 0xff,
        ]);
      }
    }
  }
  return false;
}

/// Indique si l'adresse [address] est privee, locale ou reservee.
bool _isPrivateAddress(InternetAddress address) {
  if (address.type == InternetAddressType.IPv6) {
    return _isPrivateIpv6(address.address);
  }
  final List<int> octets = address.address.split('.').map(int.parse).toList();
  return _isPrivateIpv4(octets);
}
