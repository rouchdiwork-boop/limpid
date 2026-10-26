/// La déclaration des tables du schéma, et de leur sort pendant la purge
/// d'un compte.
///
/// La déclaration est l'unique source de vérité de la purge : le magasin
/// SQL construit ses instructions à partir d'elle, le magasin en mémoire
/// efface les mêmes tables, et la suite de tests la compare aux tables du
/// schéma. Une table ajoutée au schéma sans être déclarée fait échouer le
/// test : c'est la garantie que la purge n'oublie jamais de donnée.
///
/// La déclaration vit dans le code, et non dans un commentaire : c'est elle
/// que les magasins lisent, et c'est elle que le test compare au schéma.
final class PersonalDataTables {
  const PersonalDataTables._();

  /// Les tables dont les lignes de l'auteur sont effacées par la purge.
  ///
  /// L'ordre de la liste est l'ordre de l'effacement : une table qui pointe
  /// vers une autre table vient avant elle, pour que l'effacement ne laisse
  /// jamais de référence pendante. Les livres arrivent donc en dernier, et
  /// les fils de discussion, les opérations et les collaborations avant
  /// eux.
  static const List<ErasedTable> erased = <ErasedTable>[
    ErasedTable(
      name: 'two_factor_recovery_codes',
      holds: 'les empreintes des codes de récupération',
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'two_factor',
      holds: 'le secret TOTP du compte',
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'account_plans',
      holds: 'la formule du compte et sa période',
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'quota_usage',
      holds: 'la consommation du compte',
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'api_keys',
      holds: 'les empreintes des clés d\'API, leur nom et leur dernier usage',
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'webhook_deliveries',
      holds: 'les charges utiles des livraisons : titre, résumé, ISBN',
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'webhook_endpoints',
      holds: 'les points de rappel et leur secret de signature',
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'team_invitations',
      holds: 'les invitations reçues et les invitations envoyées',
      ownerColumns: <String>['user_id', 'invited_by'],
      // L'invitation par courriel vise une adresse, pas un compte : elle
      // disparait avec le compte qui l'a recue.
      emailColumn: 'email',
    ),
    ErasedTable(
      name: 'team_members',
      holds: 'l\'appartenance aux équipes',
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'teams',
      holds: 'les équipes possédées',
      ownerColumns: <String>['owner_id'],
    ),
    ErasedTable(
      name: 'entitlements',
      holds: "les droits de lecture achetés par l'auteur",
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'promo_code_usages',
      holds: "les usages des codes promo par l'auteur",
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'book_sales',
      holds: "les prix et la ventilation des ventes des livres de l'auteur",
      ownerColumns: <String>['owner_id'],
    ),
    ErasedTable(
      name: 'project_shares',
      holds: "les partages en lecture des livres de l'auteur",
      ownerColumns: <String>['owner_id'],
    ),
    ErasedTable(
      name: 'kdp_deposits',
      holds: 'les dépôts chez Amazon et leurs refus',
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'kdp_publications',
      holds: 'les publications Amazon : titre, résumé, ISBN, éditeur',
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'comments',
      holds: 'les messages écrits par l\'auteur',
      ownerColumns: <String>['author_id'],
    ),
    ErasedTable(
      name: 'comment_threads',
      holds: 'les fils de discussion des livres de l\'auteur',
      erasesProjects: true,
    ),
    ErasedTable(
      name: 'sync_ops',
      holds:
          'les opérations écrites par l\'auteur, sur ses livres et sur '
          'ceux des autres',
      ownerColumns: <String>['author_id'],
      erasesProjects: true,
    ),
    ErasedTable(
      name: 'scenes',
      holds: 'la structure des scènes : titre, place et volume de mots',
      erasesProjects: true,
    ),
    ErasedTable(
      name: 'chapters',
      holds: 'la structure des chapitres : titre, état et liste des scènes',
      erasesProjects: true,
    ),
    ErasedTable(
      name: 'volumes',
      holds: 'la structure des tomes : titre et liste des chapitres',
      erasesProjects: true,
    ),
    ErasedTable(
      name: 'series',
      holds: 'la structure des séries : titre et liste des tomes',
      erasesProjects: true,
    ),
    ErasedTable(
      name: 'project_members',
      holds: 'les collaborations',
      ownerColumns: <String>['user_id'],
    ),
    ErasedTable(
      name: 'projects',
      holds: 'les livres',
      ownerColumns: <String>['owner_id'],
    ),
  ];

  /// Les tables dont les lignes restent, mais dont l'identifiant de
  /// l'auteur est vidé.
  ///
  /// L'indicateur de fonctionnalité est la configuration du service : il
  /// reste, sinon le service changerait de comportement sous les pieds de
  /// l'exploitant. Seule la trace de l'administrateur qui l'a changé est
  /// vidée : l'auteur ne doit pas rester identifiable dans la
  /// configuration du service.
  static const List<EmptiedTable> emptied = <EmptiedTable>[
    EmptiedTable(
      name: 'feature_flags',
      holds: 'l\'identifiant de l\'administrateur qui a changé l\'indicateur',
      column: 'updated_by',
      reason:
          'L\'indicateur est la configuration du service : il reste, '
          'mais l\'identifiant de l\'administrateur est vidé pour que '
          'l\'auteur ne reste pas identifiable dedans.',
    ),
  ];

  /// Les tables que la purge garde, et la raison de la décision.
  ///
  /// Chaque ligne porte sa raison : une table gardée sans raison écrite
  /// est une promesse d'effacement qui n'est pas tenue.
  static const List<RetainedTable> retained = <RetainedTable>[
    RetainedTable(
      name: 'audit_log',
      holds:
          'les actions de l\'auteur, son adresse électronique et son '
          'adresse IP',
      reason:
          'Le journal d\'audit est conservé un an (D-19) : il prouve la '
          'demande de suppression et la purge qui l\'a suivie. Il ne porte '
          'pas le texte des livres.',
    ),
    RetainedTable(
      name: 'account_purges',
      holds: 'l\'identifiant du compte purgé et la trace de la purge',
      reason:
          'C\'est le registre qui prouve que la purge a eu lieu, et le '
          'verrou d\'idempotence entre deux workers : effacer la ligne '
          'rendrait la purge rejouable sans fin. L\'identifiant ne renvoie '
          'plus à rien, le compte étant effacé du service d\'authentification.',
    ),
    RetainedTable(
      name: 'account_purge_deletions',
      holds: 'l\'état de l\'effacement du compte chez les tiers',
      reason:
          'C\'est la trace de l\'effacement du compte dans le service '
          'd\'authentification et dans le stockage objet : la ligne dit '
          'que la purge est complète, et elle est ce qui rend la purge '
          'reprenable.',
    ),
    RetainedTable(
      name: 'account_purge_artifacts',
      holds: 'les préfixes du stockage objet effacés',
      reason:
          'C\'est la trace des artefacts effacés. Les préfixes ne '
          'portent que l\'identifiant du projet, qui n\'existe plus.',
    ),
    RetainedTable(
      name: 'stripe_events',
      holds: 'rien : ni l\'auteur, ni son compte, ni ses données de paiement',
      reason:
          'La ligne ne porte que l\'identifiant de l\'événement Stripe, '
          'son type et l\'instant du traitement : elle est la clé '
          'd\'idempotence du webhook Stripe et ne porte aucune donnée '
          'personnelle.',
    ),
    RetainedTable(
      name: 'promo_codes',
      holds: "rien : ni l'auteur, ni son compte, ni ses livres",
      reason:
          'Les codes promo sont la configuration commerciale du service : '
          'ils sont partages par tous les comptes, et aucun ne porte '
          "l'identifiant d'un auteur. Un code cree pour un compte "
          "l'efface avec lui, mais le catalogue des codes reste.",
    ),
    RetainedTable(
      name: 'schema_migrations',
      holds: 'rien : le nom des migrations appliquées',
      reason:
          'Le registre des migrations est le suivi du schéma lui-même : '
          'il ne porte aucune donnée d\'auteur.',
    ),
  ];

  /// Les noms de toutes les tables du schéma.
  ///
  /// La liste est ce que la suite de tests compare aux tables réellement
  /// créées : une table du schéma qui n'est pas dans la liste fait échouer
  /// le test.
  static Set<String> get names => <String>{
    for (final ErasedTable table in erased) table.name,
    for (final EmptiedTable table in emptied) table.name,
    for (final RetainedTable table in retained) table.name,
  };
}

/// Une table dont les lignes de l'auteur sont effacées par la purge.
final class ErasedTable {
  /// Déclare une table effacée.
  const ErasedTable({
    required this.name,
    required this.holds,
    this.ownerColumns = const <String>[],
    this.emailColumn,
    this.erasesProjects = false,
  });

  /// Le nom de la table dans le schéma.
  final String name;

  /// Ce que la table porte de l'auteur.
  final String holds;

  /// Les colonnes qui portent l'identifiant de l'auteur.
  ///
  /// Les lignes dont une de ces colonnes porte l'identifiant de l'auteur
  /// sont effacées. Une table peut porter l'identifiant dans plusieurs
  /// colonnes : une invitation porte le compte qui la reçoit et le compte
  /// qui l'envoie, et elle disparaît dès que l'un des deux s'en va.
  final List<String> ownerColumns;

  /// La colonne qui porte l'adresse de l'auteur, quand la table en porte une.
  ///
  /// Certaines lignes visent un compte qui n'existe pas encore : une
  /// invitation d'équipe porte une adresse, et elle doit disparaître avec le
  /// compte qui l'a reçue. La purge efface alors les lignes dont l'adresse
  /// est celle du compte purgé — le compte n'est identifié que par son
  /// identifiant, l'adresse ne sert qu'ici.
  final String? emailColumn;

  /// Les lignes des projets de l'auteur sont-elles effacées aussi.
  ///
  /// Certaines lignes appartiennent à un livre plutôt qu'à un auteur : les
  /// fils de discussion et les opérations d'un projet disparaissent avec le
  /// projet qui les porte.
  final bool erasesProjects;

  /// La condition qui sélectionne les lignes de l'auteur.
  ///
  /// La condition est écrite avec les marqueurs de position de SQLite ;
  /// l'adaptateur Postgres les réécrit. Elle ne prend que des marqueurs :
  /// aucune valeur ne passe jamais par une concaténation.
  String get condition {
    final List<String> clauses = <String>[
      for (final String column in ownerColumns) '$column = ?',
      if (emailColumn != null) '$emailColumn = ?',
      if (erasesProjects)
        'project_id IN (SELECT id FROM projects WHERE owner_id = ?)',
    ];
    if (clauses.isEmpty) {
      throw StateError('The table "$name" has no condition.');
    }
    return clauses.length == 1 ? clauses.single : '(${clauses.join(' OR ')})';
  }

  /// La condition qui selectionne les lignes du proprietaire, sans son
  /// adresse.
  ///
  /// Elle ne prend que des identifiants : c'est la condition qu'un outil
  /// compte les lignes du compte — la purge, elle, atteint aussi les lignes
  /// qui portent son adresse.
  String get ownerCondition {
    final List<String> clauses = <String>[
      for (final String column in ownerColumns) '$column = ?',
      if (erasesProjects)
        'project_id IN (SELECT id FROM projects WHERE owner_id = ?)',
    ];
    if (clauses.isEmpty) {
      throw StateError('The table "$name" has no condition.');
    }
    return clauses.length == 1 ? clauses.single : '(${clauses.join(' OR ')})';
  }

  /// Le nombre d'identifiants de l'auteur que la condition prend.
  ///
  /// La condition prend un identifiant par colonne d'auteur, plus un quand
  /// elle atteint les projets de l'auteur.
  int get ownerCount => ownerColumns.length + (erasesProjects ? 1 : 0);

  /// Le nombre de colonnes d'identifiant que la condition prend.
  ///
  /// L'adresse de l'auteur, quand la table en porte une, vient **après**
  /// ces colonnes : l'ordre des paramètres de l'effacement suit l'ordre
  /// des clauses.
  int get idColumnCount => ownerColumns.length;
}

/// Une table dont les lignes restent, mais dont l'identifiant de l'auteur
/// est vidé.
final class EmptiedTable {
  /// Déclare une table dont l'identifiant de l'auteur est vidé.
  const EmptiedTable({
    required this.name,
    required this.holds,
    required this.column,
    required this.reason,
  });

  /// Le nom de la table dans le schéma.
  final String name;

  /// Ce que la table porte de l'auteur.
  final String holds;

  /// La colonne qui porte l'identifiant de l'auteur.
  final String column;

  /// Pourquoi les lignes restent, et pourquoi l'identifiant est vidé.
  final String reason;
}

/// Une table que la purge garde.
final class RetainedTable {
  /// Déclare une table gardée.
  const RetainedTable({
    required this.name,
    required this.holds,
    required this.reason,
  });

  /// Le nom de la table dans le schéma.
  final String name;

  /// Ce que la table porte de l'auteur.
  final String holds;

  /// Pourquoi la table est gardée.
  final String reason;
}
