import 'dart:typed_data';

import 'export_file_saver_io.dart'
    if (dart.library.js_interop) 'export_file_saver_web.dart';

/// Ecrit le fichier d'un export sur le poste de l'auteur.
///
/// Le fichier est binaire : il ne peut pas passer par le presse-papiers.
/// Les applications qui ont un systeme de fichiers l'ecrivent dans les
/// documents du poste ; l'application web donne le fichier au navigateur.
Future<void> saveExportFile({
  required String fileName,
  required String mimeType,
  required Uint8List bytes,
}) {
  return saveExportFileOnDevice(
    fileName: fileName,
    mimeType: mimeType,
    bytes: bytes,
  );
}
