import 'dart:async';
import 'dart:convert';

import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/auth_context.dart';
import '../auth/two_factor_guard.dart';
import '../config/app_config.dart';
import '../db/sync_op_record.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../services/access_control.dart';
import '../services/document_ownership.dart';
import '../services/sync_hub.dart';
import '../sync/sync_protocol.dart';

/// Registers the real time relay of the synchronisation.
void registerSyncSocketRoute(
  Router router,
  AppDependencies dependencies,
  AppConfig config,
) {
  router.get('/v1/sync', (Request request) {
    final Handler handler = webSocketHandler((
      WebSocketChannel channel,
      String? protocol,
    ) {
      unawaited(_handle(channel, request, dependencies));
    });
    return handler(request);
  });
}

Future<void> _handle(
  WebSocketChannel channel,
  Request request,
  AppDependencies dependencies,
) async {
  final AuthContext? auth = await _authenticate(request, dependencies);
  if (auth == null) {
    await _close(channel, <String, Object?>{
      'type': 'error',
      'payload': <String, Object?>{
        'code': ErrorCodes.unauthorized,
        'message': 'Le relais de synchronisation refuse la connexion.',
      },
    });
    return;
  }

  // Le relais applique le même contrôle de second facteur que les routes
  // HTTP : une formule qui l'exige ne passe pas par la poignée de main
  // seule. La preuve voyage dans la chaîne de requête, un navigateur ne
  // pouvant pas poser d'en-tête sur cette poignée de main.
  final TwoFactorGuard? guard = dependencies.twoFactorGuard;
  if (guard != null) {
    try {
      await guard.verifySecondFactor(auth, request);
    } on AppException catch (error) {
      await _close(channel, <String, Object?>{
        'type': 'error',
        'payload': <String, Object?>{
          'code': error.code,
          'message': error.message,
        },
      });
      return;
    }
  }

  final Map<SyncRoomKey, SyncSubscription> subscriptions =
      <SyncRoomKey, SyncSubscription>{};
  final Map<SyncRoomKey, StreamSubscription<Map<String, Object?>>> relays =
      <SyncRoomKey, StreamSubscription<Map<String, Object?>>>{};

  unawaited(
    _send(channel, <String, Object?>{
      'type': 'hello',
      'sent_at': DateTime.now().toUtc().toIso8601String(),
      'payload': <String, Object?>{'user_id': auth.userId},
    }),
  );

  final StreamSubscription<dynamic> listener = channel.stream.listen(
    (dynamic raw) => unawaited(
      _onFrame(channel, raw, auth, subscriptions, relays, dependencies),
    ),
    onDone: () {
      for (final SyncSubscription subscription in subscriptions.values) {
        dependencies.syncHub.leave(subscription);
      }
      for (final StreamSubscription<Map<String, Object?>> relay
          in relays.values) {
        relay.cancel();
      }
      subscriptions.clear();
      relays.clear();
    },
    onError: (Object error) {
      dependencies.logger.warning('sync.socket_error', <String, Object?>{
        'error': error.runtimeType.toString(),
      });
    },
    cancelOnError: false,
  );

  controllerOnCancel(channel, listener);
}

void controllerOnCancel(
  WebSocketChannel channel,
  StreamSubscription<dynamic> listener,
) {
  channel.sink.done.then((Object? _) async {
    await listener.cancel();
  });
}

Future<AuthContext?> _authenticate(
  Request request,
  AppDependencies dependencies,
) async {
  final String? token = request.url.queryParameters['token'];
  if (token == null || token.isEmpty) return null;
  try {
    return await dependencies.jwtVerifier.verify(token);
  } on AppException {
    return null;
  }
}

Future<void> _onFrame(
  WebSocketChannel channel,
  dynamic raw,
  AuthContext auth,
  Map<SyncRoomKey, SyncSubscription> subscriptions,
  Map<SyncRoomKey, StreamSubscription<Map<String, Object?>>> relays,
  AppDependencies dependencies,
) async {
  final Map<String, dynamic>? frame = _decodeFrame(raw);
  if (frame == null) {
    await _sendError(
      channel,
      ErrorCodes.validationFailed,
      'La trame reçue n\'est pas un objet JSON valide.',
    );
    return;
  }

  final Object? type = frame['type'];
  final Object? payload = frame['payload'];
  final Map<String, dynamic> body = payload is Map<String, dynamic>
      ? payload
      : const <String, dynamic>{};

  switch (type) {
    case 'ping':
      await _send(channel, <String, Object?>{'type': 'pong'});
    case 'join':
      await _join(channel, body, auth, subscriptions, relays, dependencies);
    case 'leave':
      await _leave(body, subscriptions, relays, dependencies);
    case 'op':
      await _pushOperation(channel, body, auth, subscriptions, dependencies);
    default:
      await _sendError(
        channel,
        ErrorCodes.validationFailed,
        'Le type de trame « $type » est inconnu.',
      );
  }
}

Future<void> _join(
  WebSocketChannel channel,
  Map<String, dynamic> body,
  AuthContext auth,
  Map<SyncRoomKey, SyncSubscription> subscriptions,
  Map<SyncRoomKey, StreamSubscription<Map<String, Object?>>> relays,
  AppDependencies dependencies,
) async {
  final Object? rawProjectId = body['project_id'];
  final Object? rawDocId = body['doc_id'];
  final String projectId = rawProjectId is String ? rawProjectId : '';
  final String docId = rawDocId is String ? rawDocId : '';
  if (projectId.isEmpty || docId.isEmpty) {
    await _sendError(
      channel,
      ErrorCodes.validationFailed,
      'La trame « join » doit porter « project_id » et « doc_id ».',
    );
    return;
  }

  try {
    await AccessControl.requireEditor(dependencies.projects, projectId, auth);
  } on AppException catch (error) {
    await _sendError(channel, error.code, error.message);
    return;
  }

  // Le projet doit posséder le document : un identifiant de document ne
  // suffit jamais à ouvrir une salle, et la réponse ne confirme jamais que le
  // document existe dans un autre projet.
  final bool owns = await DocumentOwnership.owns(
    dependencies.sync,
    projectId: projectId,
    docId: docId,
  );
  if (!owns) {
    final NotFoundException error = DocumentOwnership.notFound();
    await _sendError(channel, error.code, error.message);
    return;
  }

  final SyncRoomKey room = (projectId, docId);
  final SyncSubscription? previous = subscriptions[room];
  if (previous != null) dependencies.syncHub.leave(previous);
  final StreamSubscription<Map<String, Object?>>? previousRelay = relays.remove(
    room,
  );
  await previousRelay?.cancel();

  final SyncSubscription subscription = dependencies.syncHub.join(
    projectId: projectId,
    docId: docId,
    userId: auth.userId,
  );
  subscriptions[room] = subscription;

  // La subscription est annulée par `_leave`, par un nouveau `join` sur le
  // même document et à la fermeture du canal.
  // ignore: cancel_subscriptions
  final StreamSubscription<Map<String, Object?>> relay = subscription.frames
      .listen((Map<String, Object?> frame) {
        channel.sink.add(jsonEncode(frame));
      });
  relays[room] = relay;

  await _send(channel, <String, Object?>{
    'type': 'ack',
    'sent_at': DateTime.now().toUtc().toIso8601String(),
    'payload': <String, Object?>{'doc_id': docId, 'action': 'join'},
  });
  dependencies.syncHub.broadcast(projectId, docId, <String, Object?>{
    'type': 'presence',
    'sent_at': DateTime.now().toUtc().toIso8601String(),
    'payload': <String, Object?>{
      'doc_id': docId,
      'user_id': auth.userId,
      'state': 'joined',
    },
  });
}

Future<void> _leave(
  Map<String, dynamic> body,
  Map<SyncRoomKey, SyncSubscription> subscriptions,
  Map<SyncRoomKey, StreamSubscription<Map<String, Object?>>> relays,
  AppDependencies dependencies,
) async {
  final Object? rawDocId = body['doc_id'];
  final Object? rawProjectId = body['project_id'];
  final String docId = rawDocId is String ? rawDocId : '';
  if (docId.isEmpty) return;
  final String? projectId = rawProjectId is String && rawProjectId.isNotEmpty
      ? rawProjectId
      : null;

  final List<SyncRoomKey> rooms = <SyncRoomKey>[
    for (final SyncRoomKey room in subscriptions.keys)
      if (room.$2 == docId && (projectId == null || room.$1 == projectId)) room,
  ];

  for (final SyncRoomKey room in rooms) {
    final SyncSubscription? subscription = subscriptions.remove(room);
    final StreamSubscription<Map<String, Object?>>? relay = relays.remove(room);
    await relay?.cancel();
    if (subscription == null) continue;
    dependencies.syncHub.leave(subscription);
  }
}

Future<void> _pushOperation(
  WebSocketChannel channel,
  Map<String, dynamic> body,
  AuthContext auth,
  Map<SyncRoomKey, SyncSubscription> subscriptions,
  AppDependencies dependencies,
) async {
  final SyncOp op;
  try {
    op = SyncProtocol.decode(body);
  } on AppException catch (error) {
    await _sendError(channel, error.code, error.message);
    return;
  }
  final String docId = op.doc.value;

  final Object? rawProjectId = body['project_id'];
  final String? addressedProject =
      rawProjectId is String && rawProjectId.isNotEmpty ? rawProjectId : null;

  // Le projet adressé doit posséder le document : l'opération n'est ni
  // stockée ni diffusée pour un document d'un autre projet.
  final String? projectId =
      addressedProject ?? _projectOf(subscriptions, docId);
  if (projectId == null) {
    await _sendError(
      channel,
      ErrorCodes.validationFailed,
      'Cette trame « op » ne porte pas un document suivi.',
    );
    return;
  }
  final bool owns = await DocumentOwnership.owns(
    dependencies.sync,
    projectId: projectId,
    docId: docId,
  );
  if (!owns) {
    final NotFoundException error = DocumentOwnership.notFound();
    await _sendError(channel, error.code, error.message);
    return;
  }

  final SyncRoomKey? room = _roomOf(
    subscriptions,
    addressedProject: addressedProject,
    docId: docId,
  );
  if (room == null) {
    await _sendError(
      channel,
      ErrorCodes.validationFailed,
      'Cette trame « op » ne porte pas un document suivi.',
    );
    return;
  }

  final SyncOpRecord record = SyncOpRecord(
    opId: body['op_id'] as String? ?? op.operationKey,
    projectId: projectId,
    docId: docId,
    lamport: op.lamport,
    // L'auteur est l'appelant authentifié : le serveur ne fait jamais
    // confiance au `author_id` porté par la charge utile.
    authorId: auth.userId,
    type: op.kind,
    payload: _payloadOf(body),
    schemaVersion: body['schema_version'] is int
        ? body['schema_version']! as int
        : syncSchemaVersion,
    createdAt: DateTime.now().toUtc(),
  );

  await dependencies.sync.append(
    projectId: projectId,
    operations: <SyncOpRecord>[record],
  );

  dependencies.syncHub.broadcast(projectId, docId, <String, Object?>{
    'type': 'op',
    'seq': op.lamport,
    'sent_at': DateTime.now().toUtc().toIso8601String(),
    'payload': record.toJson(),
  }, except: subscriptions[room]);

  await _send(channel, <String, Object?>{
    'type': 'ack',
    'sent_at': DateTime.now().toUtc().toIso8601String(),
    'payload': <String, Object?>{'op_id': record.opId, 'doc_id': docId},
  });
}

/// The room of [docId] the caller pushes an operation for.
///
/// The room is the pair `(project, document)`: the client may address it
/// explicitly, and the server falls back on the unique room it joined for
/// this document.
SyncRoomKey? _roomOf(
  Map<SyncRoomKey, SyncSubscription> subscriptions, {
  required String? addressedProject,
  required String docId,
}) {
  if (addressedProject != null) {
    final SyncRoomKey room = (addressedProject, docId);
    return subscriptions.containsKey(room) ? room : null;
  }
  SyncRoomKey? found;
  for (final SyncRoomKey room in subscriptions.keys) {
    if (room.$2 != docId) continue;
    if (found != null) return null;
    found = room;
  }
  return found;
}

/// The project of the unique room the caller joined for [docId].
///
/// `null` when the caller joined no room for this document, or when the
/// document is ambiguous.
String? _projectOf(
  Map<SyncRoomKey, SyncSubscription> subscriptions,
  String docId,
) {
  final SyncRoomKey? room = _roomOf(
    subscriptions,
    addressedProject: null,
    docId: docId,
  );
  return room?.$1;
}

Map<String, dynamic>? _decodeFrame(dynamic raw) {
  if (raw is! String) return null;
  final Object? decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) return null;
  return decoded;
}

Map<String, dynamic> _payloadOf(Map<String, dynamic> body) {
  final Object? payload = body['payload'];
  if (payload is Map<String, dynamic>) return payload;
  return const <String, dynamic>{};
}

Future<void> _send(WebSocketChannel channel, Map<String, Object?> frame) async {
  channel.sink.add(jsonEncode(frame));
}

Future<void> _sendError(
  WebSocketChannel channel,
  String code,
  String message,
) async {
  await _send(channel, <String, Object?>{
    'type': 'error',
    'sent_at': DateTime.now().toUtc().toIso8601String(),
    'payload': <String, Object?>{'code': code, 'message': message},
  });
}

Future<void> _close(
  WebSocketChannel channel,
  Map<String, Object?> frame,
) async {
  channel.sink.add(jsonEncode(frame));
  await channel.sink.close();
}
