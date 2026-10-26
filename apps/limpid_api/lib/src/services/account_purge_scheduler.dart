import 'dart:async';

import '../logging/logger.dart';
import 'account_purge.dart';

/// The driver of the purge worker.
///
/// The scheduler runs a pass of the worker at a regular interval, on the
/// isolate of the server: there is no second process and no second HTTP
/// server. Two passes never overlap, and the scheduler is stopped when the
/// server stops.
final class AccountPurgeScheduler {
  /// Creates a scheduler.
  AccountPurgeScheduler({
    required this.service,
    required this.interval,
    required this.logger,
  });

  /// The worker the scheduler runs.
  final AccountPurgeService service;

  /// The delay between two passes.
  final Duration interval;

  /// The structured logger.
  final Logger logger;

  Timer? _timer;

  Future<void>? _pass;

  /// Whether the scheduler runs.
  bool get isRunning => _timer != null;

  /// Starts the scheduler.
  ///
  /// A first pass runs right away: a server that restarts must not wait a
  /// whole interval before erasing the accounts whose deadline passed while
  /// it was down.
  ///
  /// The method is idempotent: starting a scheduler that already runs
  /// changes nothing.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (Timer _) => unawaited(_trigger()));
    unawaited(_trigger());
  }

  /// Stops the scheduler and waits for the running pass.
  ///
  /// The method is idempotent: stopping a scheduler that never started, or
  /// that is already stopped, is a no-op.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final Future<void>? pass = _pass;
    if (pass != null) await pass;
  }

  /// Runs a pass, unless one is already running.
  ///
  /// A pass that lasts longer than the interval never overlaps with the
  /// next one: the tick is dropped.
  Future<void> _trigger() async {
    if (_pass != null) return;
    final Future<void> pass = _run();
    _pass = pass;
    try {
      await pass;
    } finally {
      _pass = null;
    }
  }

  /// Runs a pass and reports it.
  Future<void> _run() async {
    try {
      final PurgeReport report = await service.run(DateTime.now().toUtc());
      logger.info('account.purge.completed', <String, Object?>{
        'purged': report.purged.length,
        'skipped': report.skipped.length,
        'failures': report.failures.length,
      });
    } on Exception catch (error) {
      logger.warning('account.purge.error', <String, Object?>{
        'error': error.toString(),
      });
    }
  }
}
