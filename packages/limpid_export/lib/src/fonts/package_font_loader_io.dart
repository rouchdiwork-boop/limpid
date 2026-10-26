import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// La bibliotheque qui permet de localiser le paquet sur le disque.
const String _packageLibrary = 'package:limpid_export/limpid_export.dart';

/// Le racine du paquet, une fois resolue.
Directory? _packageRoot;

/// La racine du paquet `limpid_export`, ou `null` si elle est introuvable.
///
/// Le chemin est resolu via la configuration de paquets : le moteur lit
/// donc `assets/fonts/...` sans connaitre l'emplacement du depot.
Future<Directory?> _resolvePackageRoot() async {
  final cached = _packageRoot;
  if (cached != null) {
    return cached;
  }
  try {
    final uri = await Isolate.resolvePackageUri(Uri.parse(_packageLibrary));
    if (uri == null) {
      return null;
    }
    // `<paquet>/lib/limpid_export.dart` -> `<paquet>/lib` -> `<paquet>`.
    final root = File.fromUri(uri).parent.parent;
    _packageRoot = root;
    return root;
  } on Object {
    // Le paquet n'est pas resolu (application empaquetee, isolate atypique) :
    // le moteur basculera sur ses polices de substitution.
    return null;
  }
}

/// Lit un asset livre avec le paquet `limpid_export`.
///
/// Renvoie `null` si l'asset est absent ou illisible : le moteur d'export
/// bascule alors sur sa police de substitution et le signale.
Future<Uint8List?> readPackageFontAsset(String assetPath) async {
  final root = await _resolvePackageRoot();
  if (root == null) {
    return null;
  }
  final file = File.fromUri(root.uri.resolve(assetPath));
  if (!file.existsSync()) {
    return null;
  }
  try {
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  } on FileSystemException {
    return null;
  }
}
