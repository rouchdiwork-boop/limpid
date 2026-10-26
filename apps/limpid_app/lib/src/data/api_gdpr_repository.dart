import 'package:http/http.dart' as http;
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

    // Le serveur ne renvoie plus les donnees : il les.archive dans un ZIP
    // et rend une URL signee, valable quinze minutes. L'archive est
    // telechargee sans le jeton de session : l'URL porte sa propre
    // autorisation, et lui envoyer le jeton le divulguerait a l'hote.
    final String url = _stringOf(data['download_url']) ?? '';
    if (url.isEmpty) {
      throw const ApiMalformedResponseException(
        'The API did not return the download address of the archive.',
      );
    }
    final http.Response response = await client.download(Uri.parse(url));
    final Map<String, Object?> counts = _mapOf(data['counts']);

    return PersonalDataExport(
      fileName:
          _stringOf(data['file_name']) ??
          _fileNameOf(_momentOf(data['exported_at'])),
      mimeType: _stringOf(data['mime_type']) ?? 'application/zip',
      bytes: response.bodyBytes,
      generatedAt: _momentOf(data['exported_at']) ?? DateTime.now().toUtc(),
      projectCount: _intOf(counts['projects']),
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

  /// The name of the file, dated after the export.
  ///
  /// Le serveur propose son nom : celui-ci n'est qu'un repli, pour le cas
  /// ou la reponse ne le porterait pas.
  String _fileNameOf(DateTime? moment) {
    final DateTime day = moment ?? DateTime.now().toUtc();
    final String month = day.month.toString().padLeft(2, '0');
    final String date = day.day.toString().padLeft(2, '0');
    return 'limpid-donnees-${day.year}-$month-$date.zip';
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

  static String? _stringOf(Object? value) {
    if (value is String) return value;
    return null;
  }

  static int _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
