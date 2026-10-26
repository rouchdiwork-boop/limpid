import '../db/audit_entry.dart';
import '../db/audit_log.dart';
import '../db/project_record.dart';
import '../db/project_store.dart';
import '../db/quota_database.dart';
import '../db/sync_op_record.dart';
import '../db/sync_store.dart';
import '../db/team_database.dart';
import '../db/team_record.dart';
import '../db/two_factor_database.dart';
import '../db/webhook_database.dart';
import '../db/webhook_record.dart';
import '../sync/tree_builder.dart';

/// Le nombre d'entrées d'audit portées par l'export.
///
/// L'obligation de la RGPD est **toute** l'histoire du compte : le journal
/// est relu avec une borne, et cette borne est repoussée bien au-delà de ce
/// qu'un compte produit dans une vie. L'export porte donc le journal
/// entier, et non les mille dernières entrées.
const int personalDataAuditLimit = 100000;

/// Le nombre de clés et de points de rappel lus pour les réglages.
///
/// Le port des points de rappel pagine ses listes : la borne suffit pour
/// tous les comptes, et l'export dit ce qu'il n'a pas lu.
const int personalDataSettingsLimit = 1000;

/// La version du format de l'export.
///
/// Le format grandit avec le produit : la version dit à l'auteur quelle
/// forme il a reçue. La version 1 était un objet JSON renvoyé dans le corps
/// de la réponse ; la version 2 est l'archive ZIP du compte.
const int personalDataExportFormatVersion = 2;

/// Le périmètre d'un livre que l'auteur possède : le livre entier est à lui.
const String personalDataOwnerScope = 'owner';

/// Le périmètre d'un livre où l'auteur ne fait que collaborer : l'export
/// garde ses propres opérations, et rien d'autre.
const String personalDataContributionScope = 'contribution';

/// Le service qui bâtit l'export des données personnelles d'un auteur.
///
/// L'export traverse les ports de persistance : les livres, les opérations
/// du journal de synchronisation, les documents qu'ils reconstruisent, les
/// entrées d'audit de l'auteur, sa formule et sa consommation, et les
/// réglages du compte. Rien n'est inventé — chaque valeur vient du magasin
/// où elle vit.
///
/// **Aucun secret ne traverse ce service.** Le secret de la double
/// authentification, le secret d'un point de rappel et l'empreinte d'une clé
/// d'API sont des secrets, pas des données personnelles : ils sont lus dans
/// leur magasin pour y être laissés.
final class PersonalDataExportService {
  /// Crée le service.
  ///
  /// Les ports de la formule, de la double authentification, des équipes et
  /// des points de rappel sont facultatifs : un serveur qui ne sert pas
  /// ces fonctions exporte ce qu'il sait.
  const PersonalDataExportService({
    required this.projects,
    required this.sync,
    required this.audit,
    this.quotas,
    this.twoFactor,
    this.webhooks,
    this.teams,
  });

  /// Le magasin des livres.
  final ProjectStore projects;

  /// Le magasin du journal de synchronisation.
  final SyncStore sync;

  /// Le journal d'audit.
  final AuditLog audit;

  /// La formule et la consommation du compte.
  final QuotaDatabase? quotas;

  /// La double authentification du compte.
  final TwoFactorDatabase? twoFactor;

  /// Les clés d'API et les points de rappel du compte.
  final WebhookDatabase? webhooks;

  /// Les équipes du compte.
  final TeamDatabase? teams;

  /// Bâtit l'export des données personnelles de [userId].
  ///
  /// La charge utile ne porte jamais la session d'un autre auteur : les
  /// livres sont ceux que l'auteur possède ou ceux où il collabore, et les
  /// entrées d'audit sont celles qui le concernent.
  ///
  /// Elle ne porte pas non plus l'**œuvre** d'un autre auteur. Sur un livre
  /// où l'auteur ne fait que collaborer, l'export garde ses propres
  /// opérations et rien d'autre : le manuscrit d'un co-auteur n'est pas la
  /// donnée personnelle de l'auteur qui demande l'export. Sur un livre que
  /// l'auteur **possède**, le manuscrit entier est le sien — c'est son livre
  /// — et il est exporté entier.
  Future<PersonalDataExport> build({
    required String userId,
    required String email,
    DateTime? exportedAt,
  }) async {
    final DateTime moment = exportedAt ?? DateTime.now().toUtc();
    final List<PersonalDataProject> exported = await _projects(userId);

    // Le journal est relu d'une entrée de plus que la borne : quand il est
    // plus long que la borne, l'export le dit au lieu de le tronquer en
    // silence.
    final List<AuditEntry> read = await audit.entriesOf(
      userId: userId,
      limit: personalDataAuditLimit + 1,
    );
    final bool truncated = read.length > personalDataAuditLimit;

    return PersonalDataExport(
      userId: userId,
      email: email,
      exportedAt: moment,
      projects: exported,
      auditEntries: _sortedEntries(
        read.take(personalDataAuditLimit).toList(growable: false),
      ),
      auditTruncated: truncated,
      settings: await _settings(userId),
      plan: await quotas?.planOf(userId),
      usages: await quotas?.usagesOf(userId) ?? const <QuotaUsage>[],
    );
  }

  /// Les livres de l'auteur, avec leur manuscrit.
  Future<List<PersonalDataProject>> _projects(String userId) async {
    final List<ProjectRecord> owned = await projects.listAll(userId: userId);
    final List<PersonalDataProject> exported = <PersonalDataProject>[];
    for (final ProjectRecord project in owned) {
      final List<SyncOpRecord> allOperations = await sync.all(
        projectId: project.id,
      );
      final bool isOwner = project.ownerId == userId;
      final List<SyncOpRecord> operations = isOwner
          ? allOperations
          : allOperations
                .where((SyncOpRecord operation) => operation.authorId == userId)
                .toList(growable: false);
      exported.add(
        PersonalDataProject(
          project: project,
          documents: TreeBuilder.build(operations),
          operations: operations,
          scope: isOwner
              ? personalDataOwnerScope
              : personalDataContributionScope,
        ),
      );
    }
    exported.sort(
      (PersonalDataProject left, PersonalDataProject right) =>
          left.project.id.compareTo(right.project.id),
    );
    return List<PersonalDataProject>.unmodifiable(exported);
  }

  /// Les réglages du compte, sans les secrets qu'ils portent.
  Future<PersonalDataSettings> _settings(String userId) async {
    return PersonalDataSettings(
      twoFactor: await _twoFactorState(userId),
      apiKeys: await _apiKeys(userId),
      endpoints: await _endpoints(userId),
      teams: await _teams(userId),
    );
  }

  /// L'état de la double authentification, sans le secret partagé.
  Future<Map<String, Object?>> _twoFactorState(String userId) async {
    final TwoFactorRecord? record = await twoFactor?.findByUserId(userId);
    if (record == null) {
      return <String, Object?>{'is_enabled': false};
    }
    // Le secret du facteur ne quitte jamais son magasin : l'archive dit que
    // le compte en a un, et rien de plus.
    return <String, Object?>{
      'is_enabled': record.isEnabled,
      'created_at': record.createdAt.toUtc().toIso8601String(),
      'enabled_at': record.enabledAt?.toUtc().toIso8601String(),
    };
  }

  /// Les clés d'API du compte, sans leur empreinte.
  Future<List<Map<String, Object?>>> _apiKeys(String userId) async {
    final WebhookDatabase? database = webhooks;
    if (database == null) return const <Map<String, Object?>>[];
    final WebhookPage<ApiKeyRecord> page = await database.listApiKeys(
      userId: userId,
      limit: personalDataSettingsLimit,
    );
    // La représentation de la clé ne porte jamais l'empreinte : elle ne
    // quitte pas la base.
    return List<Map<String, Object?>>.unmodifiable(
      page.items.map((ApiKeyRecord record) => record.toJson()),
    );
  }

  /// Les points de rappel du compte, sans leur secret.
  Future<List<Map<String, Object?>>> _endpoints(String userId) async {
    final WebhookDatabase? database = webhooks;
    if (database == null) return const <Map<String, Object?>>[];
    final WebhookPage<WebhookEndpointRecord> page = await database
        .listEndpoints(userId: userId, limit: personalDataSettingsLimit);
    // La représentation du point de rappel ne porte jamais le secret : il
    // n'est renvoyé qu'à la création et à la rotation.
    return List<Map<String, Object?>>.unmodifiable(
      page.items.map((WebhookEndpointRecord record) => record.toJson()),
    );
  }

  /// Les équipes du compte.
  Future<List<Map<String, Object?>>> _teams(String userId) async {
    final TeamDatabase? database = teams;
    if (database == null) return const <Map<String, Object?>>[];
    final List<TeamRecord> records = await database.listTeams(userId: userId);
    return List<Map<String, Object?>>.unmodifiable(
      records.map((TeamRecord record) => record.toJson()),
    );
  }

  /// Les entrées d'audit, dans un ordre stable.
  ///
  /// Le journal est relu du plus récent au plus ancien ; l'export les range
  /// de la même façon et départage les égalités sur l'action et la cible,
  /// pour que deux exports du même compte portent les mêmes entrées dans le
  /// même ordre.
  List<AuditEntry> _sortedEntries(List<AuditEntry> entries) {
    final List<AuditEntry> sorted = List<AuditEntry>.of(entries)
      ..sort((AuditEntry left, AuditEntry right) {
        final int byDate = _momentOf(right).compareTo(_momentOf(left));
        if (byDate != 0) return byDate;
        final int byAction = left.action.compareTo(right.action);
        if (byAction != 0) return byAction;
        return left.targetId.compareTo(right.targetId);
      });
    return List<AuditEntry>.unmodifiable(sorted);
  }

  /// L'instant d'une entrée, l'aube du temps quand elle n'en a pas.
  static DateTime _momentOf(AuditEntry entry) =>
      entry.createdAt?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Les données personnelles d'un compte, rassemblées avant d'être archivées.
final class PersonalDataExport {
  /// Crée un export.
  const PersonalDataExport({
    required this.userId,
    required this.email,
    required this.exportedAt,
    required this.projects,
    required this.auditEntries,
    required this.auditTruncated,
    required this.settings,
    required this.plan,
    required this.usages,
  });

  /// L'identifiant du compte.
  final String userId;

  /// L'adresse électronique du compte.
  final String email;

  /// L'instant de l'export.
  final DateTime exportedAt;

  /// Les livres du compte, avec leur manuscrit.
  final List<PersonalDataProject> projects;

  /// L'historique du compte, le journal entier.
  final List<AuditEntry> auditEntries;

  /// Le journal a-t-il été tronqué par la borne de l'export ?
  ///
  /// La borne est hors d'atteinte d'un compte ordinaire ; quand elle est
  /// atteinte, l'archive le dit plutôt que de laisser croire que le
  /// journal s'arrête là.
  final bool auditTruncated;

  /// Les réglages du compte, sans les secrets.
  final PersonalDataSettings settings;

  /// La formule du compte, `null` quand il n'en a pas.
  final AccountPlan? plan;

  /// La consommation du compte, pour toutes les périodes.
  final List<QuotaUsage> usages;

  /// Le nombre de documents portés par l'export.
  int get documentCount => projects.fold<int>(
    0,
    (int total, PersonalDataProject project) =>
        total + project.documents.length,
  );

  /// Le nombre d'opérations portées par l'export.
  int get operationCount => projects.fold<int>(
    0,
    (int total, PersonalDataProject project) =>
        total + project.operations.length,
  );
}

/// Un livre du compte, avec le manuscrit de son auteur.
final class PersonalDataProject {
  /// Crée un livre de l'export.
  const PersonalDataProject({
    required this.project,
    required this.documents,
    required this.operations,
    required this.scope,
  });

  /// La ligne du livre.
  final ProjectRecord project;

  /// Les documents reconstruits depuis le journal.
  final List<DocumentTree> documents;

  /// Les opérations du journal, celles de l'auteur.
  final List<SyncOpRecord> operations;

  /// Le périmètre de l'export sur ce livre : `owner` ou `contribution`.
  final String scope;
}

/// Les réglages d'un compte, sans les secrets qu'ils portent.
///
/// Les réglages sont rassemblés comme des valeurs simples : le secret de la
/// double authentification, le secret d'un point de rappel et l'empreinte
/// d'une clé d'API n'entrent jamais dans cet objet.
final class PersonalDataSettings {
  /// Crée les réglages d'un compte.
  const PersonalDataSettings({
    required this.twoFactor,
    required this.apiKeys,
    required this.endpoints,
    required this.teams,
  });

  /// L'état de la double authentification.
  final Map<String, Object?> twoFactor;

  /// Les clés d'API du compte.
  final List<Map<String, Object?>> apiKeys;

  /// Les points de rappel du compte.
  final List<Map<String, Object?>> endpoints;

  /// Les équipes du compte.
  final List<Map<String, Object?>> teams;
}
