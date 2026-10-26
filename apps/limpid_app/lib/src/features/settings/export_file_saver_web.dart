import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';

/// Copies the export of the personal data in the clipboard of the browser.
///
/// The web platform has no file system the application may write in: the
/// content is copied in the clipboard, where the author saves it.
Future<void> saveExportFile(PersonalDataExport export) async {
  final String content = utf8.decode(export.bytes, allowMalformed: true);
  await Clipboard.setData(ClipboardData(text: content));
}
