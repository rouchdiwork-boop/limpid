import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Ecrit le fichier d'un export dans les documents du poste.
///
/// Le nom du fichier ne porte jamais de chemin : il vient du serveur, et un
/// serveur ne decide pas ou un fichier s'ecrit sur le poste de l'auteur.
Future<void> saveExportFileOnDevice({
  required String fileName,
  required String mimeType,
  required Uint8List bytes,
}) async {
  final Directory directory = await getApplicationDocumentsDirectory();
  final File file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
}
