import 'dart:convert';
import 'dart:math' as math;

/// Le nombre d'octets d'un secret généré par le serveur.
///
/// Trente-deux octets font 256 bits de hasard : la clé d'API et le secret de
/// signature ne sont pas devinables.
const int randomSecretBytes = 32;

/// Génère un secret aléatoire, encodé en base64 sans remplissage.
///
/// La source est [math.Random.secure] par défaut : le secret d'une clé
/// d'API et le secret de signature d'un point de rappel protègent un accès
/// et une signature, ils ne tolèrent pas une source prévisible.
String generateRandomSecret({math.Random? random}) {
  final math.Random source = random ?? math.Random.secure();
  final List<int> bytes = List<int>.generate(
    randomSecretBytes,
    (int _) => source.nextInt(256),
    growable: false,
  );
  return base64Url.encode(bytes).replaceAll('=', '');
}
