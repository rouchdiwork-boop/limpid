import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../dependencies.dart';
import '../storage/object_storage.dart';
import 'kdp_database.dart';
import 'kdp_record.dart';
import 'plan_lookup.dart';
import 'postgres_project_store.dart';
import 'postgres_sync_store.dart';
import 'project_store.dart';
import 'sync_store.dart';

/// L'implémentation Postgres de la publication Amazon KDP.
///
/// Chaque requête est paramétrée : aucune valeur n'atteint le serveur par
/// concaténation. Les colonnes JSON (`keywords`, `categories`, `issues`)
/// sont écrites en JSONB et relues comme des listes.
final class PostgresKdpDatabase implements KdpDatabase {
  /// Crée une base sur [pool].
  ///
  /// [planLookup] lit la formule du compte et [artefacts] reçoit les
  /// fichiers produits ; la composition y injecte les deux. Sans stockage
  /// injecté, la préparation répond une erreur propre au lieu d'échouer
  /// dans le moteur.
  PostgresKdpDatabase(
    Pool<Object?> pool, {
    PlanLookup? planLookup,
    ObjectStorage? artefacts,
  }) : _pool = pool,
       _planLookup = planLookup ?? _freePlan,
       _artefacts = artefacts ?? UnavailableObjectStorage(),
       _projects = PostgresProjectStore(pool),
       _sync = PostgresSyncStore(pool);

  final Pool<Object?> _pool;
  final PlanLookup _planLookup;
  final ObjectStorage _artefacts;
  final ProjectStore _projects;
  final SyncStore _sync;

  static const String _columns =
      'id, project_id, user_id, title, author, description, keywords, '
      'categories, issues, isbn, language, publisher, status, word_count, '
      'page_count, epub_key, pdf_key, epub_bytes, pdf_bytes, '
      'manuscript_version, created_at';

  /// Renvoie toujours `null` : le compte est traité comme « Gratuit ».
  static Future<String?> _freePlan(String userId) async => null;

  @override
  PlanLookup get planLookup => _planLookup;

  @override
  ProjectStore get projects => _projects;

  @override
  SyncStore get sync => _sync;

  @override
  ObjectStorage get artefacts => _artefacts;

  @override
  Future<KdpPublication> recordPublication(KdpPublication publication) async {
    await _pool.execute(
      'INSERT INTO kdp_publications ($_columns) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12, '
      '\$13, \$14, \$15, \$16, \$17, \$18, \$19, \$20, \$21)',
      parameters: <Object?>[
        publication.id,
        publication.projectId,
        publication.userId,
        publication.title,
        publication.author,
        publication.description,
        TypedValue(Type.jsonb, publication.keywords),
        TypedValue(Type.jsonb, publication.categories),
        TypedValue(Type.jsonb, _encodeIssues(publication.issues)),
        publication.isbn,
        publication.language,
        publication.publisher,
        publication.status.key,
        publication.wordCount,
        publication.pageCount,
        publication.epubKey,
        publication.pdfKey,
        publication.epubBytes,
        publication.pdfBytes,
        publication.manuscriptVersion,
        publication.createdAt,
      ],
    );
    return publication;
  }

  @override
  Future<List<KdpPublication>> listPublications({
    required String userId,
    String? projectId,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM kdp_publications '
      'WHERE user_id = \$1 AND (\$2::text IS NULL OR project_id = \$2) '
      'ORDER BY created_at DESC, id ASC',
      parameters: <Object?>[userId, projectId],
    );
    return List<KdpPublication>.unmodifiable(
      result.map(_readPublication).toList(growable: false),
    );
  }

  @override
  Future<KdpPublication?> findPublication({
    required String publicationId,
    required String userId,
  }) async {
    final Result result = await _pool.execute(
      'SELECT $_columns FROM kdp_publications '
      'WHERE id = \$1 AND user_id = \$2',
      parameters: <Object?>[publicationId, userId],
    );
    return result.isEmpty ? null : _readPublication(result.first);
  }

  static KdpPublication _readPublication(ResultRow row) {
    final Map<String, dynamic> columns = row.toColumnMap();
    return KdpPublication(
      id: columns['id']! as String,
      projectId: columns['project_id']! as String,
      userId: columns['user_id']! as String,
      title: columns['title']! as String,
      author: columns['author']! as String,
      description: columns['description']! as String,
      keywords: _readStringList(columns['keywords']),
      categories: _readStringList(columns['categories']),
      issues: _readIssues(columns['issues']),
      isbn: columns['isbn'] as String?,
      language: columns['language']! as String,
      publisher: columns['publisher'] as String?,
      status: _readStatus(columns['status']),
      wordCount: _readInt(columns['word_count']),
      pageCount: _readInt(columns['page_count']),
      epubKey: columns['epub_key']! as String,
      pdfKey: columns['pdf_key']! as String,
      epubBytes: _readInt(columns['epub_bytes']),
      pdfBytes: _readInt(columns['pdf_bytes']),
      manuscriptVersion: columns['manuscript_version']! as String,
      createdAt: _readDate(columns['created_at']),
    );
  }

  static List<Object?> _encodeIssues(List<KdpIssue> issues) {
    return <Object?>[for (final KdpIssue issue in issues) issue.toJson()];
  }

  static List<String> _readStringList(Object? value) {
    final List<Object?> decoded = _readList(value);
    return List<String>.unmodifiable(decoded.whereType<String>());
  }

  static List<KdpIssue> _readIssues(Object? value) {
    final List<KdpIssue> issues = <KdpIssue>[];
    for (final Object? entry in _readList(value)) {
      final KdpIssue? issue = _readIssue(entry);
      if (issue != null) issues.add(issue);
    }
    return List<KdpIssue>.unmodifiable(issues);
  }

  static KdpIssue? _readIssue(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final Object? code = value['code'];
    final Object? field = value['field'];
    final Object? message = value['message'];
    if (code is! String || field is! String || message is! String) {
      return null;
    }
    final Object? severity = value['severity'];
    return KdpIssue(
      code: code,
      field: field,
      message: message,
      severity: _readSeverity(severity),
    );
  }

  static KdpIssueSeverity _readSeverity(Object? value) {
    if (value is! String) return KdpIssueSeverity.blocking;
    for (final KdpIssueSeverity severity in KdpIssueSeverity.values) {
      if (severity.key == value) return severity;
    }
    return KdpIssueSeverity.blocking;
  }

  static KdpPublicationStatus _readStatus(Object? value) {
    if (value == KdpPublicationStatus.ready.key) {
      return KdpPublicationStatus.ready;
    }
    return KdpPublicationStatus.blocked;
  }

  static List<Object?> _readList(Object? value) {
    if (value is List) return value.cast<Object?>();
    if (value is String) {
      try {
        final Object? decoded = jsonDecode(value);
        if (decoded is List) return decoded.cast<Object?>();
      } on FormatException {
        return const <Object?>[];
      }
    }
    return const <Object?>[];
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw FormatException('Expected a timestamp, got ${value.runtimeType}.');
  }
}
