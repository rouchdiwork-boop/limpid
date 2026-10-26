import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_app/src/data/manuscript_store.dart';
import 'package:limpid_app/src/data/project_identity_store.dart';
import 'package:limpid_app/src/data/server_project_registry.dart';
import 'package:limpid_app/src/data/sync_api_client.dart';
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';

/// The transport that exchanges the operations with the API.
///
/// ## The registration of the project
///
/// The server refuses the operations of a project it does not know: the
/// transport therefore **declares** the project on the server before it
/// pushes the operations of that project. The declaration is idempotent — a
/// project the server already knows is never created twice — and it carries
/// the two states of the publication (D-33): the editorial stage of the
/// manuscript and the visibility of the book in the showcase.
///
/// A failure of the declaration is never swallowed: the operations stay in
/// the durable queue of the device, and the failure reaches the author
/// through the state of the synchronisation.
///
/// ## The ambiguity of `docId`
///
/// `limpid_sync` names its parameter `docId`, but the route of the API is
/// `/v1/projects/<projectId>/ops`: the server addresses a **project**, while
/// the client synchronises a **document** — a scene, in version 1
/// (ARCHITECTURE.md §5). The two identifiers are not the same, and the
/// transport is where they meet: it resolves the project of a document from
/// the local database and addresses the project route with it.
///
/// The CRDT keeps the document identifier: the operations carry the `doc_id`
/// of their scene, the snapshot of a document is keyed by that identifier,
/// and the engine refuses an operation that targets another document. The
/// project identifier only ever appears in the URL.
///
/// ## The cursor
///
/// The cursor of the API is a Lamport threshold on the operations of the
/// **project**: `GET /v1/projects/<id>/ops?since=` answers the operations
/// whose Lamport timestamp is greater than the threshold. The cursor of the
/// synchronisation client is, on the other hand, a count of the operations
/// it received for its document. The transport therefore owns the real
/// cursor — one scan position per document, persisted in the local
/// database — and ignores the one it receives.
/// A transport that can register a project on the server.
///
/// The capability extends the contract of the synchronisation: an
/// implementation that declares it knows how to tell the server that a book
/// exists. The repository of the synchronisation uses it to register the
/// books that have no scene yet — a book without a scene has no operation to
/// push, and the server would never learn about it.
abstract interface class ProjectRegisteringTransport implements SyncTransport {
  /// Registers the project [projectId] on the server.
  ///
  /// The call is idempotent: a project the server already knows is not
  /// created a second time.
  Future<void> registerProject(String projectId);
}

final class ProjectOpsTransport implements ProjectRegisteringTransport {
  /// Creates a transport.
  ProjectOpsTransport({
    required Uri baseUrl,
    required http.Client client,
    required this.store,
    required this.projects,
    AuthTokenProvider? tokenProvider,
    this.requestTimeout = defaultRequestTimeout,
    this.pageSize = defaultPullLimit,
  }) {
    _api = SyncApiClient(
      baseUrl: baseUrl,
      client: client,
      tokenProvider: tokenProvider,
      requestTimeout: requestTimeout,
    );
    _registry = ServerProjectRegistry(api: _api, identities: projects);
  }

  /// The local database, used to resolve the project of a document and to
  /// persist the cursor of the scan.
  final ManuscriptStore store;

  /// The identity of the projects on the device.
  ///
  /// The store answers what the device knows about a project, and it lets
  /// the device adopt the identifier the server minted.
  final ProjectIdentityStore projects;

  /// The timeout applied to every request.
  final Duration requestTimeout;

  /// The number of operations requested by a single page of the scan.
  final int pageSize;

  late final SyncApiClient _api;

  late final ServerProjectRegistry _registry;

  @override
  Future<PushResult> push(List<SyncOp> ops) async {
    if (ops.isEmpty) return PushResult.empty;
    final Map<String, List<SyncOp>> byProject = <String, List<SyncOp>>{};
    final List<RejectedOperation> rejected = <RejectedOperation>[];
    for (final SyncOp op in ops) {
      final String? projectId = await store.findProjectOfDocument(op.doc.value);
      if (projectId == null) {
        rejected.add(
          RejectedOperation(
            operationKey: op.operationKey,
            code: 'unknown_project',
            message: 'The document belongs to no known project.',
          ),
        );
        continue;
      }
      byProject.putIfAbsent(projectId, () => <SyncOp>[]).add(op);
    }

    final List<SyncOp> accepted = <SyncOp>[];
    final List<SyncOp> duplicated = <SyncOp>[];
    var lamportAck = 0;
    for (final MapEntry<String, List<SyncOp>> entry in byProject.entries) {
      final PushResult result = await _pushProject(entry.key, entry.value);
      accepted.addAll(result.accepted);
      duplicated.addAll(result.duplicated);
      rejected.addAll(result.rejected);
      if (result.lamportAck > lamportAck) lamportAck = result.lamportAck;
    }
    return PushResult(
      accepted: List<SyncOp>.unmodifiable(accepted),
      duplicated: List<SyncOp>.unmodifiable(duplicated),
      rejected: List<RejectedOperation>.unmodifiable(rejected),
      lamportAck: lamportAck,
    );
  }

  @override
  Future<List<SyncOp>> pull({
    required String docId,
    required int since,
    int limit = defaultPullLimit,
  }) async {
    final String? projectId = await store.findProjectOfDocument(docId);
    if (projectId == null) return const <SyncOp>[];

    var cursor = await store.readCursor(docId);
    final List<SyncOp> delivered = <SyncOp>[];
    while (delivered.length < limit) {
      final List<SyncOp> page = await _pullPage(projectId, cursor);
      if (page.isEmpty) break;
      cursor = _maxLamport(page);
      await store.writeCursor(docId, cursor);
      for (final SyncOp op in page) {
        if (op.doc.value == docId) delivered.add(op);
      }
      if (page.length < pageSize) break;
    }
    return List<SyncOp>.unmodifiable(delivered);
  }

  @override
  Stream<TransportEvent> connect(String docId) =>
      const Stream<TransportEvent>.empty();

  @override
  Future<void> dispose() async {
    // The HTTP client belongs to the application: the transport never closes
    // it.
  }

  /// Declares the project [projectId] on the server.
  ///
  /// The push declares the projects it pushes the operations of. A book that
  /// holds no scene yet has no operation to push — and the showcase would
  /// never know it. The synchronisation of the library calls this method for
  /// the projects the push never reaches.
  @override
  Future<void> registerProject(String projectId) async {
    await _registry.register(projectId);
  }

  /// Declares the project on the server, then pushes its operations.
  ///
  /// The declaration comes first: the server refuses the operations of a
  /// project it does not know. The operations travel under the identifier
  /// the server knows, which may differ from the one the device knew.
  Future<PushResult> _pushProject(String projectId, List<SyncOp> ops) async {
    final RegisteredProject project = await _registry.register(projectId);
    final Map<String, String> headers = await _api.headers();
    final String body = jsonEncode(<String, Object?>{
      'operations': ops.map(OpCodec.encode).toList(growable: false),
    });
    final http.Response response = await _api.send(
      () => _api.client.post(
        _api.uri('/v1/projects/${Uri.encodeComponent(project.id)}/ops'),
        headers: headers,
        body: body,
      ),
    );
    final Map<String, Object?> payload = _api.decodeObject(response.body);
    return PushResult(
      accepted: _decodeOperations(payload['accepted']),
      duplicated: _decodeOperations(payload['duplicated']),
      rejected: _decodeRejected(payload['rejected']),
      lamportAck: _decodeInt(payload['lamport_ack']),
    );
  }

  /// Reads a page of the journal of a project.
  Future<List<SyncOp>> _pullPage(String projectId, int cursor) async {
    final Map<String, String> headers = await _api.headers();
    final http.Response response = await _api.send(
      () => _api.client.get(
        _api.uri(
          '/v1/projects/${Uri.encodeComponent(projectId)}/ops',
          query: <String, String>{'since': '$cursor', 'limit': '$pageSize'},
        ),
        headers: headers,
      ),
    );
    final Object? payload = _api.decodeEnvelope(response.body);
    if (payload is! List<Object?>) {
      throw SyncTransportException(
        'The server did not return a list of operations.',
        code: 'sync_invalid_payload',
        statusCode: response.statusCode,
      );
    }
    return OpCodec.decodeList(payload);
  }

  /// Decodes a list of operations.
  List<SyncOp> _decodeOperations(Object? raw) {
    if (raw == null) return const <SyncOp>[];
    if (raw is! List<Object?>) {
      throw const SyncTransportException(
        'The server returned an invalid list of operations.',
        code: 'sync_invalid_payload',
      );
    }
    return OpCodec.decodeList(raw);
  }

  /// Decodes the operations the server refused.
  List<RejectedOperation> _decodeRejected(Object? raw) {
    if (raw == null) return const <RejectedOperation>[];
    if (raw is! List<Object?>) {
      throw const SyncTransportException(
        'The server returned an invalid list of rejected operations.',
        code: 'sync_invalid_payload',
      );
    }
    final List<RejectedOperation> rejected = <RejectedOperation>[];
    for (final Object? item in raw) {
      if (item is! Map<String, Object?>) continue;
      final Object? key = item['op_id'];
      final Object? code = item['code'];
      final Object? message = item['message'];
      rejected.add(
        RejectedOperation(
          operationKey: key is String ? key : 'unknown:operation',
          code: code is String ? code : 'rejected',
          message: message is String
              ? message
              : 'The server refused the operation.',
        ),
      );
    }
    return List<RejectedOperation>.unmodifiable(rejected);
  }

  /// Reads an integer of the payload.
  int _decodeInt(Object? raw) => raw is int ? raw : 0;

  /// The highest Lamport timestamp of a page.
  static int _maxLamport(List<SyncOp> page) {
    var max = 0;
    for (final SyncOp op in page) {
      if (op.lamport > max) max = op.lamport;
    }
    return max;
  }
}
