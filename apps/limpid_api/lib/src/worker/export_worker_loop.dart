import 'dart:async';

import '../db/export_job_store.dart';
import '../dependencies.dart';
import '../logging/logger.dart';
import '../services/export_service.dart';
import 'export_worker.dart';

/// L'intervalle entre deux tours de la file d'export.
///
/// Le délai est court : l'auteur attend son fichier, et le proxy coupe
/// une requête longue. Deux secondes suffisent à faire tourner le travail
/// sans faire bouillir la base.
const Duration defaultExportWorkerInterval = Duration(seconds: 2);

/// L'intervalle entre deux effacements des artefacts expirés.
///
/// L'effacement est rare : il ne porte que sur les artefacts dont les
/// quinze minutes de vie sont écoulées.
const Duration defaultExportWorkerCleanupInterval = Duration(minutes: 5);

/// Le worker d'export du serveur, prêt à démarrer.
///
/// La file [jobs] est partagée par la route et par le worker : c'est elle
/// qui porte les travaux en attente, et c'est elle qui permet à un serveur
/// de reprendre les travaux d'un serveur arrêté.
///
/// La composition du serveur démarre la boucle et l'arrête avec lui :
///
/// ```dart
/// late final ExportWorkerLoop worker;
/// final AppDependencies dependencies = AppDependencies(
///   // ...
///   shutdown: () async {
///     await worker.stop();
///     await pool.close();
///   },
/// );
/// worker = buildExportWorkerLoop(dependencies, jobs: exportJobs);
/// await worker.start();
/// ```
ExportWorkerLoop buildExportWorkerLoop(
  AppDependencies dependencies, {
  required ExportJobStore jobs,
}) {
  return ExportWorkerLoop(
    worker: ExportWorker(
      service: ExportService.forServer(dependencies, jobs: jobs),
    ),
  );
}

/// La boucle du worker d'export.
///
/// La boucle relit la file à intervalle régulier. Un serveur qui redémarre
/// **reprend les travaux restés en attente** : ils sont en attente dans la
/// base, et le premier tour de la boucle les trouve.
///
/// La boucle est **locale** au serveur : il n'y a pas de file distribuée,
/// et un serveur arrêté ne produit rien.
final class ExportWorkerLoop {
  /// Crée une boucle sur le worker [worker].
  ExportWorkerLoop({
    required this.worker,
    this.interval = defaultExportWorkerInterval,
    this.cleanupInterval = defaultExportWorkerCleanupInterval,
    this.logger,
  });

  /// Le worker que la boucle fait tourner.
  final ExportWorker worker;

  /// L'intervalle entre deux tours de la file.
  final Duration interval;

  /// L'intervalle entre deux effacements des artefacts expirés.
  final Duration cleanupInterval;

  /// Le journal du serveur, `null` quand la boucle n'en a pas.
  ///
  /// Il ne reçoit que des identifiants : ni le texte du livre, ni la trace
  /// d'exécution.
  final Logger? logger;

  Timer? _queueTimer;
  Timer? _cleanupTimer;
  Future<void>? _pending;
  bool _isStarted = false;

  /// Démarre la boucle.
  ///
  /// Le premier tour est immédiat : un serveur qui redémarre reprend ses
  /// travaux en attente sans attendre le premier intervalle.
  Future<void> start() async {
    if (_isStarted) return;
    _isStarted = true;
    await _turn();
    _queueTimer = Timer.periodic(interval, (Timer _) {
      unawaited(_turn());
    });
    _cleanupTimer = Timer.periodic(cleanupInterval, (Timer _) {
      unawaited(_cleanup());
    });
  }

  /// Arrête la boucle et attend le tour en cours.
  ///
  /// La méthode est idempotente : l'arrêter deux fois ne fait rien de plus.
  Future<void> stop() async {
    _isStarted = false;
    _queueTimer?.cancel();
    _queueTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    await _pending;
  }

  /// La boucle est-elle démarrée.
  bool get isStarted => _isStarted;

  /// Un tour de la file, jamais deux à la fois.
  Future<void> _turn() async {
    final Future<void>? pending = _pending;
    if (pending != null) {
      await pending;
      return;
    }
    final Future<void> turn = worker.drain();
    _pending = turn;
    try {
      await turn;
    } finally {
      _pending = null;
    }
  }

  /// L'effacement des artefacts expirés.
  Future<void> _cleanup() async {
    try {
      await worker.discardExpired();
    } on Object catch (error, stackTrace) {
      // L'effacement est un ménage : il ne doit jamais faire tomber la
      // boucle. Le tour suivant retentera, et la cause est journalisée.
      logger?.error('export.cleanup_failed', <String, Object?>{
        'error': error.runtimeType.toString(),
        'stack': stackTrace.toString(),
      });
    }
  }
}
