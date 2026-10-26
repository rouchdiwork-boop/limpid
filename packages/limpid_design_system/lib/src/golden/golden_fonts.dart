import 'dart:io';

import 'package:flutter/services.dart';

/// Charge des polices dans un test de temoin.
///
/// `flutter test` ne charge pas les polices declarees dans le `pubspec.yaml`
/// du paquet : sans ce chargement, le test dessine des **rectangles** a la
/// place du texte, et l'image du temoin ne prouve plus la typographie.
///
/// Le chargement est **facultatif** : une famille absente est ignoree, et le
/// temoin continue avec la police de test. Le temoin structurel, lui, n'en
/// depend pas : il ne mesure jamais le texte.
abstract final class GoldenFonts {
  /// Charge une famille de polices.
  ///
  /// Les chemins sont donnes tels que le test les voit : un chemin relatif
  /// est resolu depuis le repertoire courant du paquet.
  static Future<void> loadFamily(String family, List<String> paths) async {
    final FontLoader loader = FontLoader(family);
    bool isLoaded = false;
    for (final String path in paths) {
      final File file = File(path);
      if (!file.existsSync()) {
        continue;
      }
      final Uint8List bytes = file.readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      isLoaded = true;
    }
    if (isLoaded) {
      await loader.load();
    }
  }

  /// Charge la police des icones du SDK Flutter.
  ///
  /// Le chemin du SDK n'est pas le meme sur toutes les machines : les deux
  /// noms connus sont essayes, et l'absence de la police n'arrete rien.
  static Future<void> loadMaterialIcons() async {
    await loadFamily('MaterialIcons', _materialIconsFiles());
  }

  /// Les fichiers de la police des icones, dans le cache du SDK Flutter.
  static List<String> _materialIconsFiles() {
    final List<String> candidates = <String>[];
    final List<String> parts = Platform.resolvedExecutable.split(
      RegExp(r'[\\/]'),
    );
    final int cacheIndex = parts.lastIndexOf('cache');
    if (cacheIndex >= 0) {
      final String cache = parts.sublist(0, cacheIndex + 1).join('/');
      candidates
        ..add('$cache/artifacts/material_fonts/materialicons-regular.otf')
        ..add('$cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    }
    return candidates;
  }
}
