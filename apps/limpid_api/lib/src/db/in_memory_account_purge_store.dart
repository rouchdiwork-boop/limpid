import 'account_purge_store.dart';
import 'audit_entry.dart';
import 'personal_data_tables.dart';

/// Une ligne d'une table du schéma, en mémoire.
final class _Row {
  /// Crée une ligne.
  const _Row({required this.owners, this.projectId, this.email = ''});

  /// Les comptes auxquels la ligne appartient.
  final Set<String> owners;

  /// L'adresse que la ligne vise, quand elle en porte une.
  ///
  /// Une invitation d'equipe vise une adresse, pas un compte : elle
  /// disparait avec le compte qui l'a recue.
  final String email;

  /// Le livre auquel la ligne appartient, quand elle en a un.
  final String? projectId;
}

/// Une purge enregistrée par le magasin, en mémoire.
typedef _Purge = ({
  DateTime requestedAt,
  DateTime scheduledFor,
  DateTime purgedAt,
  String workerId,
});

/// Un [AccountPurgeStore] en mémoire, utilisé par la suite de tests.
///
/// Le magasin garde les mêmes invariants que l'implémentation SQL : il
/// efface les mêmes tables, dans l'ordre de la déclaration, et un compte
/// déjà purgé est laissé intact. C'est la déclaration des tables qui
/// commande le double : le test qui compare le double et l'implémentation
/// SQL compare donc le même périmètre des deux côtés.
///
/// Le journal lui est donné : c'est la liste des entrées du journal d'audit,
/// et le magasin ne fait que la lire.
final class InMemoryAccountPurgeStore implements AccountPurgeStore {
  /// Crée un magasin qui lit les demandes de suppression dans [entries].
  ///
  /// Les entrées sont celles du journal d'audit : le magasin ne fait que
  /// les lire.
  InMemoryAccountPurgeStore({required List<AuditEntry> entries})
    : _journal = entries;

  /// Les entrées du journal, lues par le magasin.
  final List<AuditEntry> _journal;

  /// Les lignes des tables du schéma, par table, par identifiant.
  final Map<String, Map<String, _Row>> _tables = <String, Map<String, _Row>>{};

  /// Les administrateurs qui ont changé les indicateurs, par indicateur.
  final Map<String, String> _flags = <String, String>{};

  /// Les purges déjà effectuées, par compte.
  final Map<String, _Purge> _purges = <String, _Purge>{};

  /// Ajoute un livre possédé par [ownerId] à la base.
  void addProject({required String projectId, required String ownerId}) {
    _rows('projects')[projectId] = _Row(owners: <String>{ownerId});
  }

  /// Ajoute une opération au journal de synchronisation.
  void addOperation({
    required String operationId,
    required String projectId,
    required String authorId,
  }) {
    _rows('sync_ops')[operationId] = _Row(
      owners: <String>{authorId},
      projectId: projectId,
    );
  }

  /// Ajoute une collaboration sur un livre à la base.
  void addMember({required String projectId, required String userId}) {
    _rows('project_members')['$projectId:$userId'] = _Row(
      owners: <String>{userId},
      projectId: projectId,
    );
  }

  /// Ajoute un message écrit par [authorId] à la base.
  void addMessage({required String messageId, required String authorId}) {
    _rows('comments')[messageId] = _Row(owners: <String>{authorId});
  }

  /// Ajoute une ligne appartenant à [owners] dans la table [table].
  ///
  /// La méthode ressemble à l'écriture directe en SQL : le double tient une
  /// ligne par table et par identifiant, avec les comptes auxquels elle
  /// appartient. Une ligne attachée à un livre porte son identifiant : elle
  /// disparaît avec le livre, comme le Cascade du SQL.
  void addRow({
    required String table,
    required String rowId,
    required Set<String> owners,
    String? projectId,
    String? email,
  }) {
    _rows(table)[rowId] = _Row(
      owners: owners,
      projectId: projectId,
      email: email ?? '',
    );
  }

  /// Ajoute un indicateur changé par [updatedBy].
  ///
  /// L'indicateur reste : c'est la configuration du service. La purge vide
  /// l'identifiant de l'administrateur, elle ne supprime pas l'indicateur.
  void addFeatureFlag({required String flagKey, required String updatedBy}) {
    _flags[flagKey] = updatedBy;
  }

  /// Les livres restants dans la base, par identifiant et propriétaire.
  Map<String, String> get projects {
    final Map<String, String> owners = <String, String>{};
    for (final MapEntry<String, _Row> entry in _rows('projects').entries) {
      owners[entry.key] = entry.value.owners.first;
    }
    return Map<String, String>.unmodifiable(owners);
  }

  /// Les identifiants des opérations restants dans le journal de
  /// synchronisation.
  List<String> get operationIds =>
      List<String>.unmodifiable(_rows('sync_ops').keys);

  /// Les identifiants des collaborations restantes dans la base.
  List<String> get memberIds =>
      List<String>.unmodifiable(_rows('project_members').keys);

  /// Les comptes déjà purgés.
  Set<String> get purgedAccounts => Set<String>.unmodifiable(_purges.keys);

  /// Les administrateurs qui ont changé les indicateurs, par indicateur.
  Map<String, String> get featureFlagOwners =>
      Map<String, String>.unmodifiable(_flags);

  /// Le nombre de lignes du compte restées dans la base.
  ///
  /// La méthode compte les lignes de l'auteur dans toutes les tables
  /// personnelles : c'est la mesure que la suite de tests compare entre le
  /// double et l'implémentation SQL.
  int remainingRows(String userId) {
    int total = 0;
    for (final ErasedTable table in PersonalDataTables.erased) {
      for (final _Row row in _rows(table.name).values) {
        if (_belongsTo(row, userId)) total++;
      }
    }
    return total;
  }

  @override
  Future<List<AuditEntry>> journalEntries({
    required String action,
    required int limit,
  }) async {
    final List<AuditEntry> matching =
        _journal
            .where((AuditEntry entry) => entry.action == action)
            .toList(growable: false)
          ..sort((AuditEntry left, AuditEntry right) {
            final int byDate = _momentOf(left).compareTo(_momentOf(right));
            if (byDate != 0) return byDate;
            return left.targetId.compareTo(right.targetId);
          });
    return List<AuditEntry>.unmodifiable(matching.take(limit));
  }

  @override
  Future<AccountPurgeOutcome> purge({
    required String userId,
    String? email,
    required DateTime requestedAt,
    required DateTime scheduledFor,
    required DateTime purgedAt,
    required String workerId,
  }) async {
    final _Purge? existing = _purges[userId];
    if (existing != null) {
      return AccountPurgeOutcome(
        userId: userId,
        projectsDeleted: 0,
        operationsDeleted: 0,
        collaborationsDeleted: 0,
        messagesDeleted: 0,
        personalRowsDeleted: 0,
        purged: false,
      );
    }

    _purges[userId] = (
      requestedAt: requestedAt,
      scheduledFor: scheduledFor,
      purgedAt: purgedAt,
      workerId: workerId,
    );

    final Map<String, int> erased = <String, int>{};
    int total = 0;
    for (final ErasedTable table in PersonalDataTables.erased) {
      final int count = _erase(table.name, userId, email);
      erased[table.name] = count;
      total += count;
    }
    total += _emptyFlags(userId);

    return AccountPurgeOutcome(
      userId: userId,
      projectsDeleted: erased['projects'] ?? 0,
      operationsDeleted: erased['sync_ops'] ?? 0,
      collaborationsDeleted: erased['project_members'] ?? 0,
      messagesDeleted: erased['comments'] ?? 0,
      personalRowsDeleted: total,
      purged: true,
    );
  }

  /// Les lignes de la table [table], la table étant créée à la demande.
  Map<String, _Row> _rows(String table) =>
      _tables.putIfAbsent(table, () => <String, _Row>{});

  /// Si la ligne appartient au compte [userId].
  ///
  /// Une ligne appartient au compte quand elle porte son identifiant, ou
  /// quand elle est attachée à un livre qu'il possède : c'est le Cascade du
  /// SQL, la ligne d'un livre disparaît avec le livre.
  bool _belongsTo(_Row row, String userId) {
    if (row.owners.contains(userId)) return true;
    final String? projectId = row.projectId;
    if (projectId == null) return false;
    final _Row? project = _rows('projects')[projectId];
    return project != null && project.owners.contains(userId);
  }

  /// Efface les lignes de la table [table] qui appartiennent au compte
  /// [userId], et rend leur nombre.
  int _erase(String table, String userId, String? email) {
    final ErasedTable? declared = _declarationOf(table);
    final String address = email ?? '';
    return _removeMatching(
      _rows(table),
      (_Row row) =>
          _belongsTo(row, userId) ||
          (declared?.emailColumn != null &&
              address.isNotEmpty &&
              row.email == address),
    );
  }

  /// La declaration de la table [name], quand elle en a une.
  ErasedTable? _declarationOf(String name) {
    for (final ErasedTable table in PersonalDataTables.erased) {
      if (table.name == name) return table;
    }
    return null;
  }

  /// Vide l'identifiant de l'administrateur des indicateurs qu'il a
  /// changés, et rend leur nombre.
  ///
  /// L'indicateur reste : c'est la configuration du service. Seul
  /// l'identifiant de l'administrateur est vidé, pour que l'auteur ne reste
  /// pas identifiable dedans.
  int _emptyFlags(String userId) {
    final List<String> keys = <String>[];
    for (final MapEntry<String, String> entry in _flags.entries) {
      if (entry.value == userId) keys.add(entry.key);
    }
    for (final String key in keys) {
      _flags[key] = '';
    }
    return keys.length;
  }

  /// L'instant d'une entrée, l'époque quand elle n'en porte pas.
  static DateTime _momentOf(AuditEntry entry) =>
      entry.createdAt?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Retire les lignes qui satisfont [test] et rend leur nombre.
  ///
  /// Les lignes sont rassemblées avant d'être retirées : le retrait d'une
  /// ligne ne doit jamais changer la réponse du test de la suivante.
  static int _removeMatching<V>(
    Map<String, V> rows,
    bool Function(V value) test,
  ) {
    final List<String> keys = <String>[];
    for (final MapEntry<String, V> entry in rows.entries) {
      if (test(entry.value)) keys.add(entry.key);
    }
    for (final String key in keys) {
      rows.remove(key);
    }
    return keys.length;
  }
}
