import '../db/export_job_record.dart';
import '../services/export_service.dart';

/// Le worker des travaux d'export.
///
/// Le worker prend le travail en attente le plus ancien et le produit. Il
/// ne porte aucune règle : la fabrication du livre, la jauge du stockage et
/// la consommation vivent dans le service, et le worker ne fait que les
/// demander dans l'ordre.
///
/// Le worker est **local** au serveur : il n'y a pas de file distribuée.
final class ExportWorker {
  /// Crée un worker sur le service [service].
  const ExportWorker({required this.service});

  /// Le service qui produit les travaux.
  final ExportService service;

  /// Produit le travail en attente le plus ancien.
  ///
  /// La méthode rend `null` quand la file est vide : le worker n'a alors
  /// rien à faire.
  ///
  /// Le travail rendu est **fini** : il a réussi ou il a échoué. Un
  /// travail qui resterait en attente bloquerait la file.
  Future<ExportJobRecord?> runNext() async {
    final List<ExportJobRecord> queued = await service.jobs.listQueued(
      limit: 1,
    );
    if (queued.isEmpty) return null;
    return service.run(queued.first);
  }

  /// Vide la file : produit tous les travaux en attente.
  ///
  /// La méthode rend le nombre de travaux produits. Elle s'arrête au
  /// premier travail qui échoue : le travail suivant est repris au tour
  /// suivant, et l'erreur ne bloque pas toute la file.
  Future<int> drain() async {
    var produced = 0;
    while (true) {
      final ExportJobRecord? job = await runNext();
      if (job == null) return produced;
      produced++;
      if (job.status == ExportJobStatus.failed) return produced;
    }
  }

  /// Efface les artefacts expirés.
  Future<int> discardExpired() => service.discardExpired();
}
