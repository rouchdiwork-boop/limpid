import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Le delai avant que l'adresse temporaire du fichier soit liberee.
///
/// Le navigateur commence le telechargement quand le lien est clique.
const Duration _releaseDelay = Duration(seconds: 2);

/// Le type du fichier, quand le serveur n'en nomme pas.
const String _fallbackMimeType = 'application/octet-stream';

/// Donne le fichier d'un export au navigateur.
///
/// L'application web n'a pas de systeme de fichiers ou elle puisse ecrire :
/// le fichier est donne au navigateur, qui le range dans les telechargements
/// de l'auteur sous le nom que le serveur a propose.
Future<void> saveExportFileOnDevice({
  required String fileName,
  required String mimeType,
  required Uint8List bytes,
}) async {
  final String type = mimeType.isEmpty ? _fallbackMimeType : mimeType;
  final web.Blob blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: type),
  );
  final String address = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement anchor =
      web.document.createElement('a') as web.HTMLAnchorElement
        ..href = address
        ..download = fileName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();

  await Future<void>.delayed(_releaseDelay);
  web.URL.revokeObjectURL(address);
}
