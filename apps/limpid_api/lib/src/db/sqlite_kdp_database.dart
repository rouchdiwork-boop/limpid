import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../dependencies.dart';
import '../storage/object_storage.dart';
import 'kdp_database.dart';
import 'kdp_record.dart';
import 'plan_lookup.dart';
import 'project_store.dart';
import 'sqlite_database.dart';
import 'sqlite_project_store.dart';
import 'sqlite_sync_store.dart';
import 'sqlite_values.dart';
import 'sync_store.dart';

/// L'implémentation SQLite de la publication Amazon KDP.
///
/// L'adaptateur est la traduction de celui de Postgres : mêmes requêtes,
/// même ordre de tri et mêmes invariants. Chaque requête est paramétrée :
/// aucune valeur n'atteint le moteur par concaténation.
///
/// Les colonnes JSON sont des `TEXT` qui portent le document encodé, la
/// convention du dialecte SQLite. Les horodatages sont stockés en
/// microsecondes depuis l'époque Unix (voir `SqliteValues`).
final class SqliteKdpDatabase implements KdpDatabase {
  /// Crée une base sur [database].
  ///
  /// [planLookup] lit la formule du compte et [artefacts] reçoit les
  /// fichiers produits ; la composition y injecte les deux. Sans stockage
  /// injecté, la préparation répond une erreur propre au lieu d'échouer
  /// dans le moteur.
  SqliteKdpDatabase(
    SqliteDatabase database, {
    PlanLookup? planLookup,
    ObjectStorage? artefacts,
  }) : _database = database,
       _planLookup = planLookup ?? _freePlan,
       _artefacts = artefacts ?? UnavailableObjectStorage(),
       _projects = SqliteProjectStore(database),
       _sync = SqliteSyncStore(database);

  final SqliteDatabase _database;
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
    return _database.run(() {
      _database.connection.execute(
        'INSERT INTO kdp_publications ($_columns) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          publication.id,
          publication.projectId,
          publication.userId,
          publication.title,
          publication.author,
          publication.description,
          jsonEncode(publication.keywords),
          jsonEncode(publication.categories),
          jsonEncode(_encodeIssues(publication.issues)),
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
          SqliteValues.encodeTimestamp(publication.createdAt),
        ],
      );
      return publication;
    });
  }

  @override
  Future<List<KdpPublication>> listPublications({
    required String userId,
    String? projectId,
  }) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM kdp_publications '
        'WHERE user_id = ? AND (? IS NULL OR project_id = ?) '
        'ORDER BY created_at DESC, id ASC',
        <Object?>[userId, projectId, projectId],
      );
      return List<KdpPublication>.unmodifiable(
        result.map(_readPublication).toList(growable: false),
      );
    });
  }

  @override
  Future<KdpPublication?> findPublication({
    required String publicationId,
    required String userId,
  }) async {
    return _database.run(() {
      final ResultSet result = _database.connection.select(
        'SELECT $_columns FROM kdp_publications '
        'WHERE id = ? AND user_id = ?',
        <Object?>[publicationId, userId],
      );
      return result.isEmpty ? null : _readPublication(result.first);
    });
  }

  static KdpPublication _readPublication(Row row) {
    return KdpPublication(
      id: row['id']! as String,
      projectId: row['project_id']! as String,
      userId: row['user_id']! as String,
      title: row['title']! as String,
      author: row['author']! as String,
      description: row['description']! as String,
      keywords: _readStringList(row['keywords']),
      categories: _readStringList(row['categories']),
      issues: _readIssues(row['issues']),
      isbn: row['isbn'] as String?,
      language: row['language']! as String,
      publisher: row['publisher'] as String?,
      status: _readStatus(row['status']),
      wordCount: SqliteValues.decodeInt(row['word_count']),
      pageCount: SqliteValues.decodeInt(row['page_count']),
      epubKey: row['epub_key']! as String,
      pdfKey: row['pdf_key']! as String,
      epubBytes: SqliteValues.decodeInt(row['epub_bytes']),
      pdfBytes: SqliteValues.decodeInt(row['pdf_bytes']),
      manuscriptVersion: row['manuscript_version']! as String,
      createdAt: SqliteValues.decodeTimestamp(row['created_at']),
    );
  }

  static List<Object?> _encodeIssues(List<KdpIssue> issues) {
    return <Object?>[for (final KdpIssue issue in issues) issue.toJson()];
  }

  static List<String> _readStringList(Object? value) {
    return List<String>.unmodifiable(_readList(value).whereType<String>());
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
}
