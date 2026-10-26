import 'dart:async';
import 'dart:io';

import 'package:limpid_api/limpid_api.dart';

export 'package:limpid_api/limpid_api.dart' show createServer;

/// Starts the API and waits for the termination signal.
///
/// The configuration is validated when the process boots: a missing or
/// malformed environment variable stops the server before it accepts a
/// request.
Future<void> main(List<String> arguments) async {
  final AppConfig config;
  try {
    config = AppConfig.fromEnvironment(Platform.environment);
  } on AppException catch (error) {
    stderr.writeln('Configuration invalide : ${error.message}');
    exitCode = 78;
    return;
  }

  final Logger logger = Logger(level: config.logLevel);
  final AppDependencies dependencies = await buildProductionDependencies(
    config,
  );
  final HttpServer server = await createServer(
    config,
    dependencies: dependencies,
  );

  logger.info('server.listening', <String, Object?>{
    'port': server.port,
    'address': server.address.address,
  });

  final Completer<void> shutdown = Completer<void>();
  final List<StreamSubscription<ProcessSignal>> signals =
      <StreamSubscription<ProcessSignal>>[
        // Windows does not deliver SIGTERM: watching it there aborts the
        // process right after the socket is opened.
        if (!Platform.isWindows)
          ProcessSignal.sigterm.watch().listen((ProcessSignal signal) {
            logger.info('server.signal', <String, Object?>{
              'signal': signal.toString(),
            });
            if (!shutdown.isCompleted) shutdown.complete();
          }),
        ProcessSignal.sigint.watch().listen((ProcessSignal signal) {
          logger.info('server.signal', <String, Object?>{
            'signal': signal.toString(),
          });
          if (!shutdown.isCompleted) shutdown.complete();
        }),
      ];

  await shutdown.future;
  logger.info('server.stopping', <String, Object?>{});
  await server.close(force: true);
  for (final StreamSubscription<ProcessSignal> signal in signals) {
    await signal.cancel();
  }
  // The database connection and the cache are released here: a SQLite file
  // left open would keep its write-ahead log on disk.
  await dependencies.close();
  logger.info('server.stopped', <String, Object?>{});
}
