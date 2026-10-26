import 'export_job_record.dart';
import 'export_job_store.dart';

/// L'implémentation en mémoire du port [ExportJobStore].
///
/// Le magasin garde les travaux dans une carte : la suite de tests s'en
/// sert, et un serveur de démonstration peut s'en servir aussi. Les travaux
/// disparaissent avec le processus : c'est le magasin Postgres ou SQLite
/// qui porte la file d'un vrai serveur.
final class InMemoryExportJobStore implements ExportJobStore {
  /// Crée un magasin vide.
  InMemoryExportJobStore();

  final Map<String, ExportJobRecord> _jobs = <String, ExportJobRecord>{};

  /// Les travaux actuellement gardés, pour les assertions de la suite.
  List<ExportJobRecord> get jobs =>
      List<ExportJobRecord>.unmodifiable(_jobs.values);

  @override
  Future<ExportJobRecord?> findById(String id) async => _jobs[id];

  @override
  Future<ExportJobRecord> insert(ExportJobRecord record) async {
    _jobs[record.id] = record;
    return record;
  }

  @override
  Future<void> update(ExportJobRecord record) async {
    _jobs[record.id] = record;
  }

  @override
  Future<List<ExportJobRecord>> listQueued({int limit = 50}) async {
    final List<ExportJobRecord> queued =
        _jobs.values
            .where(
              (ExportJobRecord job) => job.status == ExportJobStatus.queued,
            )
            .toList(growable: false)
          ..sort((ExportJobRecord left, ExportJobRecord right) {
            final int byDate = left.createdAt.compareTo(right.createdAt);
            if (byDate != 0) return byDate;
            return left.id.compareTo(right.id);
          });
    return List<ExportJobRecord>.unmodifiable(queued.take(limit));
  }

  @override
  Future<List<ExportJobRecord>> listByUser({
    required String userId,
    int limit = 50,
  }) async {
    final List<ExportJobRecord> owned =
        _jobs.values
            .where((ExportJobRecord job) => job.userId == userId)
            .toList(growable: false)
          ..sort((ExportJobRecord left, ExportJobRecord right) {
            final int byDate = right.createdAt.compareTo(left.createdAt);
            if (byDate != 0) return byDate;
            return left.id.compareTo(right.id);
          });
    return List<ExportJobRecord>.unmodifiable(owned.take(limit));
  }

  @override
  Future<List<ExportJobRecord>> listExpired({
    required DateTime now,
    int limit = 50,
  }) async {
    final List<ExportJobRecord> expired =
        _jobs.values
            .where(
              (ExportJobRecord job) =>
                  job.status == ExportJobStatus.succeeded &&
                  job.isExpiredAt(now),
            )
            .toList(growable: false)
          ..sort((ExportJobRecord left, ExportJobRecord right) {
            final DateTime leftExpiry = left.expiresAt!;
            final DateTime rightExpiry = right.expiresAt!;
            final int byDate = leftExpiry.compareTo(rightExpiry);
            if (byDate != 0) return byDate;
            return left.id.compareTo(right.id);
          });
    return List<ExportJobRecord>.unmodifiable(expired.take(limit));
  }
}
