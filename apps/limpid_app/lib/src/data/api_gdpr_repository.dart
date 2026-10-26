import 'dart:convert';
import 'dart:typed_data';

import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/gdpr_repository.dart';

/// The personal data of the author, served by the API.
///
/// The two routes answer the obligations of the RGPD (D-19):
/// - `GET /v1/me/export` returns the whole personal data of the author;
/// - `DELETE /v1/me` registers the deletion request of the account.
///
/// The client never lets a raw exception escape: a failure is always one of
/// the typed errors of `domain/errors.dart`, or the
/// `ServiceUnavailableException` of the demonstration mode.
final class ApiGdprRepository implements GdprRepository {
  /// Creates a repository on top of [client].
  const ApiGdprRepository({required this.client});

  /// The client of the API.
  final ApiClient client;

  @override
  Future<PersonalDataExport> exportPersonalData() async {
    final Object? payload = await client.get('/v1/me/export');
    final Map<String, Object?> data = _objectOf(payload);
    final Map<String, Object?> account = _mapOf(data['account']);
    final DateTime? exportedAt = _momentOf(account['exported_at']);

    return PersonalDataExport(
      fileName: _fileNameOf(exportedAt),
      mimeType: 'application/json',
      bytes: _encode(data),
      generatedAt: exportedAt ?? DateTime.now().toUtc(),
      projectCount: _countOf(data['projects']),
    );
  }

  @override
  Future<AccountDeletion> requestAccountDeletion() async {
    final Object? payload = await client.delete(
      '/v1/me',
      body: <String, Object?>{'confirm': true},
    );
    final Map<String, Object?> data = _objectOf(payload);
    final DateTime requestedAt =
        _momentOf(data['requested_at']) ?? DateTime.now().toUtc();
    final DateTime scheduledFor =
        _momentOf(data['scheduled_for']) ?? requestedAt;

    return AccountDeletion(
      requestedAt: requestedAt,
      scheduledFor: scheduledFor,
      retentionDays: _intOf(data['retention_days']),
    );
  }

  /// Encodes the payload of the export as a readable file.
  Uint8List _encode(Map<String, Object?> payload) {
    final String encoded = const JsonEncoder.withIndent('  ').convert(payload);
    return Uint8List.fromList(utf8.encode(encoded));
  }

  /// The name of the file, dated after the export.
  String _fileNameOf(DateTime? moment) {
    final DateTime day = moment ?? DateTime.now().toUtc();
    final String month = day.month.toString().padLeft(2, '0');
    final String date = day.day.toString().padLeft(2, '0');
    return 'limpid-donnees-${day.year}-$month-$date.json';
  }

  static Map<String, Object?> _objectOf(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const ApiMalformedResponseException(
      'The API did not return the expected payload.',
    );
  }

  static Map<String, Object?> _mapOf(Object? value) {
    if (value is Map<String, Object?>) return value;
    return const <String, Object?>{};
  }

  static DateTime? _momentOf(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static int _countOf(Object? value) {
    if (value is List<dynamic>) return value.length;
    return 0;
  }

  static int _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
