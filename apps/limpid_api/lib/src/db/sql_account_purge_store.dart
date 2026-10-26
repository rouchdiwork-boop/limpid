import 'account_purge_store.dart';
import 'audit_entry.dart';
import 'personal_data_tables.dart';

/// Le magasin de la purge, adossé au SQL.
///
/// L'effacement se fait dans une seule transaction : le registre des purges
/// et les lignes du compte disparaissent ensemble, ou rien ne se passe. Le
/// registre est aussi la condition de l'effacement : une instruction
/// n'efface que ce qui est marqué « à purger ».
final class SqlAccountPurgeStore implements AccountPurgeStore {
  /// Crée un magasin sur [database].
  const SqlAccountPurgeStore(this._database);

  /// Le port SQL du magasin.
  final AccountPurgeDatabase _database;

  /// L'instruction qui ouvre le registre des purges.
  ///
  /// La clause `ON CONFLICT` est le verrou entre deux workers : le premier
  /// qui écrit la ligne possède la purge, le second n'écrit rien.
  static const String _ledgerInsert =
      'INSERT INTO account_purges '
      '(user_id, requested_at, scheduled_for, purged_at, purged_by) '
      'VALUES (?, ?, ?, ?, ?) ON CONFLICT (user_id) DO NOTHING';

  /// La condition qui laisse une instruction effacer les lignes du compte.
  ///
  /// La ligne du registre est écrite par la transaction de la purge, avec
  /// l'instant exact de la purge. Une purge qui trouve le compte déjà purgé
  /// garde l'instant de la première : ses instructions ne touchent à rien,
  /// et les lignes écrites après la première purge survivent.
  static const String _holdsLedger =
      'EXISTS (SELECT 1 FROM account_purges '
      'WHERE user_id = ? AND purged_at = ?)';

  /// L'index de l'instruction qui ouvre le registre.
  static const int _ledger = 0;

  /// La valeur écrite dans la colonne d'un indicateur dont l'auteur est
  /// effacé.
  ///
  /// La colonne porte une valeur non nulle : une valeur vide signifie
  /// « administrateur inconnu », ce que la colonne porte déjà par défaut.
  static const String _noAdministrator = '';

  @override
  Future<List<AuditEntry>> journalEntries({
    required String action,
    required int limit,
  }) async {
    final List<Map<String, Object?>> rows = await _database.query(
      'SELECT id, user_id, action, target_type, target_id, metadata, ip, '
      'created_at FROM audit_log WHERE action = ? '
      'ORDER BY created_at ASC, id ASC LIMIT ?',
      <Object?>[action, limit],
    );
    return List<AuditEntry>.unmodifiable(rows.map(_readEntry));
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
    final List<int> counts = await _database.transaction(
      _statements(
        userId: userId,
        email: email,
        requestedAt: requestedAt,
        scheduledFor: scheduledFor,
        purgedAt: purgedAt,
        workerId: workerId,
      ),
    );
    return AccountPurgeOutcome(
      userId: userId,
      projectsDeleted: counts[_indexOfErased('projects')],
      operationsDeleted: counts[_indexOfErased('sync_ops')],
      collaborationsDeleted: counts[_indexOfErased('project_members')],
      messagesDeleted: counts[_indexOfErased('comments')],
      personalRowsDeleted: _erasedRows(counts),
      purged: counts[_ledger] > 0,
    );
  }

  /// Les instructions de la purge, dans l'ordre où elles sont exécutées.
  ///
  /// Les instructions viennent de la déclaration des tables : la purge ne
  /// connaît que les tables qu'elle déclare, et la suite de tests compare
  /// la déclaration aux tables du schéma. Une table ajoutée au schéma sans
  /// être déclarée fait donc échouer le test.
  ///
  /// L'ordre suit les dépendances : une table qui pointe vers une autre
  /// table est effacée avant elle. Les livres arrivent en dernier, parce
  /// que les instructions qui précèdent lisent les livres du compte pour
  /// savoir quelles lignes leur appartiennent.
  ///
  /// Chaque instruction porte la condition du registre : seul le compte
  /// marqué « à purger » est effacé, et un compte déjà purgé est laissé
  /// intact.
  List<(String, List<Object?>)> _statements({
    required String userId,
    String? email,
    required DateTime requestedAt,
    required DateTime scheduledFor,
    required DateTime purgedAt,
    required String workerId,
  }) {
    final Object? stamp = _database.encodeTimestamp(purgedAt);
    final List<(String, List<Object?>)> statements = <(String, List<Object?>)>[
      (
        _ledgerInsert,
        <Object?>[
          userId,
          _database.encodeTimestamp(requestedAt),
          _database.encodeTimestamp(scheduledFor),
          stamp,
          workerId,
        ],
      ),
    ];
    for (final ErasedTable table in PersonalDataTables.erased) {
      statements.add((
        'DELETE FROM ${table.name} WHERE ${table.condition} AND $_holdsLedger',
        <Object?>[
          // Les colonnes d'identifiant portent l'identifiant du compte, puis
          // l'adresse quand la table en porte une, puis le compte des
          // projets : l'ordre des clauses est celui des parametres.
          ...List<Object?>.filled(table.idColumnCount, userId),
          if (table.emailColumn != null) email ?? '',
          ...List<Object?>.filled(table.erasesProjects ? 1 : 0, userId),
          userId,
          stamp,
        ],
      ));
    }
    for (final EmptiedTable table in PersonalDataTables.emptied) {
      statements.add((
        'UPDATE ${table.name} SET ${table.column} = ? '
            'WHERE ${table.column} = ? AND $_holdsLedger',
        <Object?>[_noAdministrator, userId, userId, stamp],
      ));
    }
    return statements;
  }

  /// L'index de l'instruction qui efface les lignes de la table [table].
  ///
  /// L'instruction du registre vient en premier, les instructions
  /// d'effacement suivent dans l'ordre de la déclaration.
  static int _indexOfErased(String table) {
    final int position = PersonalDataTables.erased.indexWhere(
      (ErasedTable declared) => declared.name == table,
    );
    if (position < 0) {
      throw StateError('The table "$table" is not declared as erased.');
    }
    return position + 1;
  }

  /// Le nombre de lignes de l'auteur effacées par la purge.
  ///
  /// Le registre est la première instruction : il ne compte pas. Toutes les
  /// autres effacent une ligne de l'auteur, ou vident son identifiant.
  static int _erasedRows(List<int> counts) {
    int total = 0;
    for (int index = _ledger + 1; index < counts.length; index++) {
      total += counts[index];
    }
    return total;
  }

  /// Lit une entrée du journal depuis sa ligne.
  AuditEntry _readEntry(Map<String, Object?> row) {
    return AuditEntry(
      userId: _text(row, 'user_id'),
      action: _text(row, 'action'),
      targetType: _text(row, 'target_type'),
      targetId: _text(row, 'target_id'),
      metadata: _database.decodeJson(row['metadata']),
      ip: row['ip'] as String?,
      createdAt: _database.decodeTimestamp(row['created_at']),
    );
  }

  /// Lit une colonne de texte, une chaîne vide quand elle manque.
  static String _text(Map<String, Object?> row, String column) {
    final Object? value = row[column];
    return value is String ? value : '';
  }
}
