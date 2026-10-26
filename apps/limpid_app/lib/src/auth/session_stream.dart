import 'dart:async';

import 'package:limpid_app/src/auth/auth_repository.dart';

/// The stream of the session of the current author.
///
/// The current session is replayed **synchronously** when the stream is
/// listened to. The router reads the session before the first frame: when
/// the session arrives asynchronously, the sign-in screen is shown for one
/// frame before the application redirects to the dashboard. The synchronous
/// replay removes the flash.
final class SessionStream extends Stream<AuthSession?> {
  /// Creates the stream.
  const SessionStream({required this.current, required this.updates});

  /// The session to replay when the stream is listened to.
  final AuthSession? Function() current;

  /// The live updates of the session.
  final Stream<AuthSession?> updates;

  @override
  bool get isBroadcast => false;

  @override
  StreamSubscription<AuthSession?> listen(
    void Function(AuthSession?)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    late final StreamSubscription<AuthSession?> live;
    final controller = StreamController<AuthSession?>(
      sync: true,
      onCancel: () => live.cancel(),
    );
    final replay = controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    live = updates.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    // The listener is attached: the controller delivers the session now.
    //
    // The consumers that collect the events without a handler — `first` and
    // its friends — cancel their subscription as soon as they receive a
    // value they cannot deliver, and install their handler right after the
    // subscription. The replay waits for them.
    if (onData == null) {
      scheduleMicrotask(() => controller.add(current()));
    } else {
      controller.add(current());
    }
    return replay;
  }
}
