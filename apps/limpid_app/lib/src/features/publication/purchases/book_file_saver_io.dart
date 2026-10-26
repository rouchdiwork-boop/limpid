import 'dart:io';

import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:path_provider/path_provider.dart';

/// Ecrit le fichier d'un livre acheté dans les documents du poste.
///
/// Le nom du fichier vient du serveur, mais il ne garde que son dernier
/// segment : un serveur ne décide pas du chemin d'écriture sur le poste de
/// l'acheteur.
Future<void> saveBookFile(BookFile file) async {
  final Directory directory = await getApplicationDocumentsDirectory();
  final File target = File('${directory.path}/${file.fileName}');
  await target.writeAsBytes(file.bytes, flush: true);
}
