import 'export_job_record.dart';

/// Le port de persistance des travaux d'export.
///
/// Le port porte la table `export_jobs` et rien d'autre : ni la fabrication
/// du livre, ni le compte de la consommation, ni la durée de vie de
/// l'artefact. Ces règles vivent dans le service d'export, et le port se
/// contente de garder les travaux.
///
/// Les implémentations sont **en mémoire**, **Postgres** et **SQLite**.
abstract interface class ExportJobStore {
  /// Le travail [id], `null` quand il n'existe pas.
  Future<ExportJobRecord?> findById(String id);

  /// Enregistre un travail nouveau.
  ///
  /// Le travail est rendu tel qu'il a été rangé : l'identifiant et les
  /// instants sont posés par l'appelant, la base ne les invente pas.
  Future<ExportJobRecord> insert(ExportJobRecord record);

  /// Range le travail [record], qui remplace la ligne précédente.
  Future<void> update(ExportJobRecord record);

  /// Les travaux en attente, les plus anciens d'abord.
  ///
  /// La liste est bornée par [limit] : le worker prend le premier travail
  /// de la file, il n'en charge pas la table entière.
  Future<List<ExportJobRecord>> listQueued({int limit});

  /// Les travaux du compte [userId], les plus récents d'abord.
  Future<List<ExportJobRecord>> listByUser({required String userId, int limit});

  /// Les travaux dont l'artefact a expiré à l'instant [now].
  ///
  /// Ce sont les travaux que le worker efface : l'artefact a disparu du
  /// stockage, la ligne ne sert plus à rien.
  Future<List<ExportJobRecord>> listExpired({required DateTime now, int limit});
}
