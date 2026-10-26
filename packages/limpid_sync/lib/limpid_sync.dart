/// The synchronisation client of Limpid.
///
/// The package moves the CRDT operations of `limpid_core` between the
/// device and the API, and guarantees the promise of the product: the
/// application is fully usable offline, the operations pile up in a durable
/// queue, and the replicas converge when the network comes back.
///
/// The package is pure Dart: it never imports `package:flutter/*`, so it
/// can be tested with `dart test` without a device and without a database.
///
/// ## Name collision with `limpid_core`
///
/// `limpid_core` also declares a `SyncTransport`, with a different and much
/// narrower contract (it only pushes and pulls, it knows nothing about the
/// queue, the cursor or the real-time channel).
///
/// The transport of `limpid_sync` is the one the application must use. When
/// both packages are imported, hide the transport of `limpid_core`:
///
/// ```dart
/// import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
/// import 'package:limpid_sync/limpid_sync.dart';
/// ```
library;

export 'src/conflict.dart';
export 'src/conflict_detector.dart';
export 'src/db/drift_op_queue_store.dart';
export 'src/db/drift_snapshot_store.dart';
export 'src/db/sync_database.dart';
export 'src/errors.dart';
export 'src/network_status.dart';
export 'src/queue/memory_op_queue_store.dart';
export 'src/queue/op_queue.dart';
export 'src/queue/op_queue_store.dart';
export 'src/queue/queued_op.dart';
export 'src/queue/retry_policy.dart';
export 'src/snapshot_store.dart';
export 'src/sync_client.dart';
export 'src/sync_events.dart';
export 'src/sync_state.dart';
export 'src/transport/auth_token_provider.dart';
export 'src/transport/http_sync_transport.dart';
export 'src/transport/op_codec.dart';
export 'src/transport/sync_transport.dart';
export 'src/transport/web_socket_sync_transport.dart';
