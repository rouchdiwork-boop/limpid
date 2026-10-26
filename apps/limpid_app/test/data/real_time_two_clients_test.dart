import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_sync_repository.dart';
import 'package:limpid_app/src/data/real_time_transport.dart';
import 'package:limpid_app/src/data/relay_channel.dart';
import 'package:limpid_app/src/domain/realtime.dart';
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart' hide SyncStatus;

import 'support.dart';

/// The delay the propagation of an operation must stay under.
///
/// The criterion of the lot 2 : « la propagation entre deux clients actifs
/// reste sous 300 ms en p95 ». La mesure sur deux machines reste dans la
/// liste de pré-livraison : le test mesure le chemin complet, pas le réseau.
const Duration _kPropagationBudget = Duration(milliseconds: 300);

void main() {
  late AppDatabase aliceDatabase;
  late AppDatabase bobDatabase;
  late LoopbackRelay relay;
  late LocalSyncRepository alice;
  late LocalSyncRepository bob;

  setUp(() async {
    aliceDatabase = await openMemoryDatabase();
    bobDatabase = await openMemoryDatabase();
    await _indexDocument(aliceDatabase);
    await _indexDocument(bobDatabase);

    relay = LoopbackRelay('document-1');
    alice = _repositoryOf(aliceDatabase, relay.channelOf('alice'));
    bob = _repositoryOf(bobDatabase, relay.channelOf('bob'));
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
    await aliceDatabase.close();
    await bobDatabase.close();
  });

  test('the operation of a client reaches the other one and changes the '
      'document', () async {
    final StreamSubscription<RealTimeEvent> aliceEvents = alice
        .follow('document-1')
        .listen((_) {});
    addTearDown(aliceEvents.cancel);
    final StreamSubscription<RealTimeEvent> bobEvents = bob
        .follow('document-1')
        .listen((_) {});
    addTearDown(bobEvents.cancel);
    await _pump();

    final SyncOp operation = insertBlockOp(
      documentId: 'document-1',
      lamport: 7,
      authorId: 'auteur-2',
      blockId: 'block-7',
      text: 'Le vent se lève.',
    );

    final Stopwatch watch = Stopwatch()..start();
    relay.send(operation);
    await _pump();
    watch.stop();

    // Le document de l'autre client porte le texte de l'opération.
    final DocumentSnapshot? snapshot = await aliceDatabase
        .snapshotsFor(() => 'author-1')
        .read(const DocumentId('document-1'));
    expect(snapshot, isNotNull);
    expect(snapshot!.operations, hasLength(1));
    expect(snapshot.operations.single.lamport, 7);

    final CrdtDocument document = snapshot.restore();
    expect(document.blocks, hasLength(1));
    expect(document.blocks.single.content.plainText, 'Le vent se lève.');

    // Et la propagation est mesurée.
    expect(watch.elapsed, lessThan(_kPropagationBudget));
  });

  test('the same operation received twice is applied once', () async {
    final StreamSubscription<RealTimeEvent> aliceEvents = alice
        .follow('document-1')
        .listen((_) {});
    addTearDown(aliceEvents.cancel);
    await _pump();

    final SyncOp operation = insertBlockOp(
      documentId: 'document-1',
      lamport: 7,
      authorId: 'auteur-2',
    );

    relay.send(operation);
    await _pump();
    relay.send(operation);
    await _pump();

    final DocumentSnapshot? snapshot = await aliceDatabase
        .snapshotsFor(() => 'author-1')
        .read(const DocumentId('document-1'));
    expect(snapshot!.operations, hasLength(1));
    expect(snapshot.restore().blocks, hasLength(1));
  });

  test('the presence of a client reaches the other one', () async {
    final List<RealTimeEvent> events = <RealTimeEvent>[];
    final StreamSubscription<RealTimeEvent> aliceEvents = alice
        .follow('document-1')
        .listen(events.add);
    addTearDown(aliceEvents.cancel);
    await _pump();

    relay.sendPresence(
      const PresencePeer(
        docId: 'document-1',
        userId: 'auteur-2',
        state: PresenceState.joined,
      ),
    );
    await _pump();

    final RealTimePresence received = events
        .whereType<RealTimePresence>()
        .single;
    expect(received.peer.userId, 'auteur-2');
    expect(received.peer.state, PresenceState.joined);
  });
}

/// Builds a repository whose relay is the channel of [channel].
LocalSyncRepository _repositoryOf(AppDatabase database, RelayChannel channel) {
  final _SilentRestTransport rest = _SilentRestTransport();
  return LocalSyncRepository(
    database: database,
    transport: rest,
    author: const AuthorId('author-1'),
    realTime: RealTimeTransport(
      baseUrl: Uri.parse('https://api.test'),
      store: database.manuscripts,
      rest: rest,
      channelFactory: (String docId) => channel,
    ),
  );
}

/// Indexes a document, so the synchronisation knows the project it belongs
/// to.
Future<void> _indexDocument(AppDatabase database) async {
  await database.manuscripts.saveProject(projectOf());
  await database.manuscripts.saveChapter(chapterOf(), projectId: 'project-1');
  await database.manuscripts.saveScene(sceneOf(), projectId: 'project-1');
}

/// The relay of the test: it carries the frames from a client to the other.
///
/// The relay of the test replaces the WebSocket du serveur : il ne fait que
/// transporter les trames, comme le vrai.
final class LoopbackRelay {
  LoopbackRelay(this.documentId);

  /// The document the clients follow.
  final String documentId;

  /// The channels of the clients.
  final Map<String, LoopbackChannel> _channels = <String, LoopbackChannel>{};

  /// The channel of the client [name].
  LoopbackChannel channelOf(String name) {
    return _channels.putIfAbsent(name, () => LoopbackChannel(documentId));
  }

  /// Sends [operation] to every client.
  void send(SyncOp operation) {
    for (final LoopbackChannel channel in _channels.values) {
      channel.emit(
        TransportOperationsReceived(documentId, <SyncOp>[operation]),
      );
    }
  }

  /// Announces the presence of [peer] to every client.
  void sendPresence(PresencePeer peer) {
    for (final LoopbackChannel channel in _channels.values) {
      channel.emit(TransportPresenceReceived(documentId, peer));
    }
  }
}

/// The channel of a client of the relay of the test.
final class LoopbackChannel implements RelayChannel {
  LoopbackChannel(this.documentId);

  /// The document the channel follows.
  final String documentId;

  final StreamController<TransportEvent> _controller =
      StreamController<TransportEvent>.broadcast();

  /// The cursors the client announced.
  final List<PresenceCursor> cursors = <PresenceCursor>[];

  @override
  Stream<TransportEvent> events(String docId) => _controller.stream;

  @override
  Future<void> publishCursor(String docId, PresenceCursor cursor) async {
    cursors.add(cursor);
  }

  @override
  Future<void> close() async {
    if (_controller.isClosed) return;
    await _controller.close();
  }

  /// Publishes [event] towards the client.
  void emit(TransportEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }
}

/// A REST transport that answers nothing.
final class _SilentRestTransport implements SyncTransport {
  @override
  Future<PushResult> push(List<SyncOp> ops) async => PushResult.empty;

  @override
  Future<List<SyncOp>> pull({
    required String docId,
    required int since,
    int limit = defaultPullLimit,
  }) async => const <SyncOp>[];

  @override
  Stream<TransportEvent> connect(String docId) =>
      const Stream<TransportEvent>.empty();

  @override
  Future<void> dispose() async {}
}

/// Lets the pending microtasks and timers run.
Future<void> _pump([Duration delay = const Duration(milliseconds: 20)]) async {
  await Future<void>.delayed(delay);
}
