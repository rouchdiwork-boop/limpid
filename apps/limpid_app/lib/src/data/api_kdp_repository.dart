import 'package:limpid_app/src/data/api_client.dart';
import 'package:limpid_app/src/domain/errors.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';

/// La publication d'un livre chez Amazon KDP, servie par l'API.
///
/// Les trois routes de publication décrivent le cycle du dossier : la
/// préparation produit les fichiers et contrôle le dossier, la liste et la
/// lecture rendent la trace. La route de dépôt remet le dossier à Amazon et
/// rend son verdict.
///
/// Le refus d'Amazon n'est pas une panne : la route répond avec la trace,
/// dont la liste des problèmes se lit comme celle du contrôle de soumission.
/// Une panne, elle, est signalée par [KdpUnavailableException] : le livre
/// n'est pas parti, et l'application le dit.
final class ApiKdpRepository implements KdpRepository {
  /// Crée un dépôt sur le dessus de [client].
  const ApiKdpRepository({required this.client});

  /// Le client de l'API.
  final ApiClient client;

  @override
  Future<List<KdpSubmission>> list() async {
    final Object? payload = await client.get('/v1/publishing/kdp');
    if (payload is! List<Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the list of the submissions.',
      );
    }
    return List<KdpSubmission>.unmodifiable(payload.map(_submissionOf));
  }

  @override
  Future<KdpSubmission?> find(String submissionId) async {
    final Object? payload = await client.get(
      '/v1/publishing/kdp/${Uri.encodeComponent(submissionId)}',
    );
    if (payload is! Map<String, Object?>) {
      throw const ApiMalformedResponseException(
        'The API did not return the submission.',
      );
    }
    return _submissionOf(payload);
  }

  @override
  Future<KdpSubmission> prepare({
    required String projectId,
    required KdpMetadata metadata,
  }) async {
    // Les métadonnées sont contrôlées avant l'envoi : le serveur ne doit
    // pas recevoir un ISBN qui ne portera jamais une clé de contrôle.
    final KdpFieldError? error = metadata.validate();
    if (error != null) throw KdpValidationException(error);

    final Object? payload = await client.post(
      '/v1/publishing/kdp',
      body: <String, Object?>{
        'project_id': projectId,
        'title': metadata.composedTitle,
        'author': metadata.author.trim(),
        'description': metadata.description.trim(),
        'keywords': metadata.keywords,
        'categories': metadata.categories,
        'isbn': metadata.normalizedIsbn,
        'language': metadata.language.trim(),
        'publisher': metadata.publisher.trim(),
      },
    );
    return _submissionOf(payload);
  }

  @override
  Future<KdpSubmission> deposit({required String submissionId}) async {
    final Map<String, Object?> deposit = await _deposit(submissionId);
    // La route du dépôt rend le dépôt, pas la publication : la trace du
    // dossier est relue pour que l'écran montre le livre et son verdict.
    final KdpSubmission? submission = await find(submissionId);
    if (submission == null) {
      throw const ApiMalformedResponseException(
        'The API did not return the submission of the deposit.',
      );
    }
    return submission.copyWith(
      state: _depositStateOf(_stringOf(deposit['status'])),
      refusal: _refusalOf(deposit),
      depositId: _stringOf(deposit['id']),
      amazonSubmissionId: _stringOf(deposit['amazon_submission_id']),
      attempts: _intOf(deposit['attempts']) ?? 0,
      updatedAt: _momentOf(deposit['updated_at']),
    );
  }

  /// Dépose le dossier et rend la trace du dépôt.
  ///
  /// Le serveur répond une panne quand la distribution Amazon n'est pas
  /// configurée, ou quand Amazon ne répond pas. La panne devient une
  /// [KdpUnavailableException] : l'écran dit que le livre n'est pas parti.
  Future<Map<String, Object?>> _deposit(String submissionId) async {
    final Object? payload;
    try {
      payload = await client.post(
        '/v1/publishing/kdp/deposits',
        body: <String, Object?>{'publication_id': submissionId},
      );
    } on ApiServerException catch (error) {
      if (error.code == 'service_unavailable') {
        throw KdpUnavailableException(reason: error.message);
      }
      rethrow;
    }
    return _objectOf(payload, 'the deposit');
  }

  /// La publication portée par la réponse du serveur.
  static KdpSubmission _submissionOf(Object? payload) {
    final Map<String, Object?> json = _objectOf(payload, 'the submission');
    return KdpSubmission(
      id: _stringOf(json['id']) ?? '',
      projectId: _stringOf(json['project_id']) ?? '',
      title: _stringOf(json['title']) ?? '',
      author: _stringOf(json['author']) ?? '',
      description: _stringOf(json['description']) ?? '',
      keywords: _stringsOf(json['keywords']),
      categories: _stringsOf(json['categories']),
      language: _stringOf(json['language']) ?? '',
      publisher: _stringOf(json['publisher']) ?? '',
      isbn: _stringOf(json['isbn']),
      state: KdpState.draft,
      isReady: _stringOf(json['status']) == 'ready',
      issues: _issuesOf(json['issues']),
      wordCount: _intOf(json['word_count']) ?? 0,
      pageCount: _intOf(json['page_count']) ?? 0,
      createdAt: _momentOf(json['created_at']) ?? DateTime.now().toUtc(),
    );
  }

  /// L'état porté par le statut d'un dépôt.
  ///
  /// Le dépôt en attente est un dossier déjà remis à Amazon : il porte
  /// l'état « déposé », le même que le dossier qu'Amazon a accepté.
  static KdpState _depositStateOf(String? status) => switch (status) {
    'rejected' => KdpState.refused,
    'failed' => KdpState.failed,
    _ => KdpState.submitted,
  };

  /// Le motif d'un refus d'Amazon.
  ///
  /// Le motif est `null` quand Amazon a accepté le dossier : rien n'a été
  /// reproché, et l'écran n'invente pas de reproche.
  static KdpRefusal? _refusalOf(Map<String, Object?> deposit) {
    final List<KdpIssue> issues = _issuesOf(deposit['issues']);
    final String? reason = _stringOf(deposit['failure_reason']);
    if (issues.isEmpty && reason == null) return null;
    return KdpRefusal(issues: issues, reason: reason);
  }

  /// Les problèmes portés par une réponse du serveur.
  static List<KdpIssue> _issuesOf(Object? raw) {
    if (raw is! List<Object?>) return const <KdpIssue>[];
    return List<KdpIssue>.unmodifiable(raw.map(_issueOf).whereType<KdpIssue>());
  }

  /// Un problème porté par une réponse du serveur.
  static KdpIssue? _issueOf(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final String code = _stringOf(raw['code']) ?? 'amazon_refused';
    final String message = _stringOf(raw['message']) ?? '';
    return KdpIssue(
      code: code,
      field: _stringOf(raw['field']) ?? 'manuscript',
      message: message.isEmpty ? code : message,
      severity: _severityOf(raw['severity']),
    );
  }

  /// La gravité d'un problème.
  static KdpIssueSeverity _severityOf(Object? value) {
    if (value == 'warning') return KdpIssueSeverity.warning;
    return KdpIssueSeverity.blocking;
  }

  /// Les mots-clés ou les catégories d'une réponse du serveur.
  static List<String> _stringsOf(Object? raw) {
    if (raw is! List<Object?>) return const <String>[];
    return List<String>.unmodifiable(
      raw.whereType<String>().map((String value) => value.trim()),
    );
  }

  /// Un objet JSON, ou une réponse refusée.
  static Map<String, Object?> _objectOf(Object? value, String what) {
    if (value is Map<String, Object?>) return value;
    throw ApiMalformedResponseException('The API did not return $what.');
  }

  /// Un texte, `null` quand le serveur n'en envoie pas.
  static String? _stringOf(Object? value) {
    if (value is String) return value;
    return null;
  }

  /// Un nombre, `null` quand le serveur n'en envoie pas.
  static int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  /// Un instant, `null` quand le serveur n'en envoie pas.
  static DateTime? _momentOf(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
