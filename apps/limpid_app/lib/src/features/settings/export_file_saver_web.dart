import 'dart:js_interop';

import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:web/web.dart' as web;

/// The delay before the temporary address of the archive is released.
///
/// The browser starts the download when the anchor is clicked. Releasing the
/// address immediately can cancel the download in some browsers: a short
/// wait costs nothing and removes the doubt.
const Duration _releaseDelay = Duration(seconds: 2);

/// The media type of the archive, when the server does not name one.
const String _fallbackMimeType = 'application/zip';

/// Downloads the export of the personal data from the browser.
///
/// The web platform has no file system the application may write in: the
/// archive est donnee au navigateur, qui la range dans les telechargements
/// de l'auteur sous le nom que le serveur a propose.
///
/// Une **archive** ne peut pas passer par le presse-papiers : le fichier
/// est binaire, et l'auteur doit pouvoir l'ouvrir.
Future<void> saveExportFile(PersonalDataExport export) async {
  final String mimeType = export.mimeType.isEmpty
      ? _fallbackMimeType
      : export.mimeType;
  final web.Blob blob = web.Blob(
    <JSAny>[export.bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final String address = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement anchor =
      web.document.createElement('a') as web.HTMLAnchorElement
        ..href = address
        ..download = export.fileName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();

  await Future<void>.delayed(_releaseDelay);
  web.URL.revokeObjectURL(address);
}
