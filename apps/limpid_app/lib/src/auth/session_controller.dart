import 'dart:async';

import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:limpid_app/src/auth/supabase_auth_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_controller.g.dart';

/// Exposes the session of the current author.
///
/// The value is `null` when nobody is signed in. The stream never throws: an
/// authentication outage leaves the author signed out rather than breaking the
/// interface.
///
/// The stream of the repository is returned as is, and not through an
/// asynchronous generator: the repository replays the session synchronously,
/// and the router reads the session before the first frame. An asynchronous
/// generator would delay the session and flash the sign-in screen.
@Riverpod(keepAlive: true)
Stream<AuthSession?> sessionController(Ref ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.watchSession().transform(
    StreamTransformer.fromHandlers(
      handleError:
          (Object error, StackTrace stackTrace, EventSink<AuthSession?> sink) {
            sink.add(null);
          },
    ),
  );
}
