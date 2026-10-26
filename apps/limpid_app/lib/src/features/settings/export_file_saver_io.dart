import 'dart:io';

import 'package:limpid_app/src/domain/gdpr_repository.dart';
import 'package:path_provider/path_provider.dart';

/// Writes the export of the personal data in the documents of the device.
///
/// The application offers the file to the author: the desktop and the
/// mobile platforms have a file system, the web platform has not.
Future<void> saveExportFile(PersonalDataExport export) async {
  final Directory directory = await getApplicationDocumentsDirectory();
  final File file = File('${directory.path}/${export.fileName}');
  await file.writeAsBytes(export.bytes, flush: true);
}
