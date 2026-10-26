import 'dart:typed_data';

/// Lit un asset livre avec le paquet `limpid_export`.
///
/// Hors plateforme `dart:io` (le web), il n'y a pas de systeme de fichiers :
/// la lecture echoue toujours et le moteur d'export utilise ses polices de
/// substitution.
Future<Uint8List?> readPackageFontAsset(String assetPath) async {
  return null;
}
