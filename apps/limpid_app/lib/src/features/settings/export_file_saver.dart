import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:limpid_app/src/features/export/export_file_saver.dart';

/// Saves the export of the personal data outside of the application.
///
/// The desktop and the mobile applications write the file in the documents
/// of the device; the web application has no file system, and the browser
/// downloads the archive itself.
///
/// The file is an **archive**, not a text: it can never go through the
/// clipboard, which would corrupt it.
Future<void> savePersonalDataExport(PersonalDataExport export) {
  return saveExportFile(
    fileName: export.fileName,
    mimeType: export.mimeType,
    bytes: export.bytes,
  );
}
