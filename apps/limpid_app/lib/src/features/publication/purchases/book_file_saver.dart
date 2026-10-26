/// L'enregistrement du fichier d'un livre acheté.
///
/// Le fichier vient du serveur et il est binaire : il ne peut pas passer
/// par le presse-papiers. L'enregistrement est donc une opération de la
/// plateforme : le port la décrit, et la plateforme la réalise.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/book_sale_repository.dart';

import 'book_file_saver_io.dart'
    if (dart.library.js_interop) 'book_file_saver_web.dart';

/// Le port qui enregistre le fichier d'un livre acheté hors de
/// l'application.
///
/// Le desktop et le mobile écrivent le fichier dans les documents du poste ;
/// le web n'a pas de système de fichiers, et le navigateur range le
/// fichier dans ses téléchargements.
abstract interface class BookFileSaver {
  /// Enregistre le fichier [file] hors de l'application.
  Future<void> save(BookFile file);
}

/// L'enregistrement du fichier, par la plateforme de l'application.
final bookFileSaverProvider = Provider<BookFileSaver>((Ref ref) {
  return const PlatformBookFileSaver();
});

/// L'enregistrement du fichier par la plateforme de l'application.
final class PlatformBookFileSaver implements BookFileSaver {
  /// Crée l'enregistrement.
  const PlatformBookFileSaver();

  @override
  Future<void> save(BookFile file) => saveBookFile(file);
}
