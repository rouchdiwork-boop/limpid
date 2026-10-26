import 'package:limpid_app/src/domain/gdpr_repository.dart';

import 'export_file_saver_io.dart'
    if (dart.library.js_interop) 'export_file_saver_web.dart';

/// Saves the export of the personal data outside of the application.
///
/// The desktop and the mobile applications write the file in the documents
/// of the device; the web application has no file system and copies the
/// content in the clipboard of the browser instead.
Future<void> savePersonalDataExport(PersonalDataExport export) =>
    saveExportFile(export);
