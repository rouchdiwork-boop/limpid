import 'dart:js_interop';

import 'package:limpid_app/src/domain/book_sale_repository.dart';
import 'package:web/web.dart' as web;

/// Le delai avant que l'adresse temporaire du fichier soit liberee.
///
/// Le navigateur commence le telechargement quand l'ancre est cliquee.
/// Liberer l'adresse aussitot peut annuler le telechargement dans
/// certains navigateurs : une courte attente ne coute rien et leve le
/// doute.
const Duration _releaseDelay = Duration(seconds: 2);

/// Le type du fichier, quand son extension ne dit rien.
const String _fallbackMimeType = 'application/octet-stream';

/// Les types des fichiers que l'application vend, par extension.
const Map<String, String> _mimeTypes = <String, String>{
  '.epub': 'application/epub+zip',
  '.pdf': 'application/pdf',
  '.docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.html': 'text/html',
  '.md': 'text/markdown',
  '.txt': 'text/plain',
};

/// Telecharge le fichier d'un livre acheté depuis le navigateur.
///
/// Le web n'a pas de systeme de fichiers que l'application puisse ecrire :
/// le fichier est donne au navigateur, qui le range dans les
/// telechargements de l'acheteur sous le nom que le serveur a propose.
Future<void> saveBookFile(BookFile file) async {
  final web.Blob blob = web.Blob(
    <JSAny>[file.bytes.toJS].toJS,
    web.BlobPropertyBag(type: _mimeTypeOf(file.fileName)),
  );
  final String address = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement anchor =
      web.document.createElement('a') as web.HTMLAnchorElement
        ..href = address
        ..download = file.fileName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();

  await Future<void>.delayed(_releaseDelay);
  web.URL.revokeObjectURL(address);
}

/// Le type du fichier, deduit de son extension.
String _mimeTypeOf(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot < 0) return _fallbackMimeType;
  return _mimeTypes[fileName.substring(dot).toLowerCase()] ?? _fallbackMimeType;
}
