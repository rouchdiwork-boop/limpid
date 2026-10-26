import 'package:drift/native.dart';
import 'package:limpid_app/src/data/app_database.dart';
import 'package:limpid_app/src/data/local_account_scope.dart';
import 'package:limpid_app/src/data/local_manuscript_repository.dart';
import 'package:limpid_app/src/data/local_preferences_repository.dart';
import 'package:limpid_app/src/data/local_sync_repository.dart';
import 'package:limpid_core/limpid_core.dart' hide SyncTransport;
import 'package:limpid_sync/limpid_sync.dart';

/// The account that is signed in on the device during a test.
///
/// The account changes when the author signs out and another one signs in:
/// the scope of the local data follows it, exactly like the session does.
final class SignedInAccount {
  /// Creates the account that is signed in.
  SignedInAccount([this.accountId = firstAccount]);

  /// The identifier of the first account of the tests.
  static const String firstAccount = 'author-a';

  /// The identifier of the second account of the tests.
  static const String secondAccount = 'author-b';

  /// The identifier of the account that is signed in.
  String accountId;

  /// The identifier of the account, as the resolver of the scope.
  String resolve() => accountId;
}

/// The device of the tests: the local database and the repositories of the
/// account that is signed in.
final class SharedDevice {
  /// Creates a device.
  const SharedDevice({
    required this.database,
    required this.account,
    required this.transport,
    required this.manuscripts,
    required this.preferences,
    required this.sync,
  });

  /// The local database of the device.
  final AppDatabase database;

  /// The account that is signed in.
  final SignedInAccount account;

  /// The server the synchronisation talks to.
  final RecordingTransport transport;

  /// The manuscripts of the account that is signed in.
  final LocalManuscriptRepository manuscripts;

  /// The preferences of the account that is signed in.
  final LocalPreferencesRepository preferences;

  /// The synchronisation of the account that is signed in.
  final LocalSyncRepository sync;

  /// The operations waiting to be sent for the account that is signed in.
  Future<List<QueuedOp>> pendingOperations() async {
    final OpQueue queue = OpQueue(store: database.queueFor(account.resolve));
    return queue.pending();
  }
}

/// Opens a device: a local database and the repositories of an account.
///
/// The scope of the local data follows [SignedInAccount]: the repositories
/// read and write the data of the account that is signed in, exactly like
/// they do when the session changes.
Future<SharedDevice> openSharedDevice() async {
  final SignedInAccount account = SignedInAccount();
  final AppDatabase database = await AppDatabase.openWith(
    NativeDatabase.memory(),
    accountScope: LocalAccountScope(account.resolve),
  );
  final RecordingTransport transport = RecordingTransport();
  return SharedDevice(
    database: database,
    account: account,
    transport: transport,
    manuscripts: LocalManuscriptRepository(
      database: database,
      author: const AuthorId(SignedInAccount.firstAccount),
      currentAuthor: () => AuthorId(account.accountId),
    ),
    preferences: LocalPreferencesRepository(
      database: database,
      accountId: account.resolve,
    ),
    sync: LocalSyncRepository(
      database: database,
      transport: transport,
      author: const AuthorId(SignedInAccount.firstAccount),
      currentAuthor: () => AuthorId(account.accountId),
    ),
  );
}

/// Builds an operation inserting a block in [documentId].
InsertBlockOp insertBlockOp({
  required String documentId,
  required String authorId,
  String blockId = 'block-1',
  int lamport = 1,
}) => InsertBlockOp(
  doc: DocumentId(documentId),
  lamport: lamport,
  author: AuthorId(authorId),
  blockId: BlockId(blockId),
  parent: null,
  order: OrderKey('5'),
  type: BlockType.paragraph,
  content: const TextContent('Il pleuvait sur la falaise.'),
);

/// Builds a project owned by [authorId].
Project projectOf({
  String id = 'project-1',
  String authorId = SignedInAccount.firstAccount,
  String title = 'Les Heures de Cendre',
}) => Project(
  id: ProjectId(id),
  ownerId: AuthorId(authorId),
  title: title,
  synopsis: '',
  status: ManuscriptStatus.draft,
  isPublic: false,
  order: OrderKey.initial,
  chapterIds: const <ChapterId>[],
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: DateTime.utc(2026, 10, 1),
);

/// Builds a chapter of a project.
Chapter chapterOf({String id = 'chapter-1'}) => Chapter(
  id: ChapterId(id),
  title: 'Le premier chapitre',
  order: OrderKey('5'),
  sceneIds: const <SceneId>[],
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: DateTime.utc(2026, 10, 1),
);

/// Builds a scene of a chapter, written today.
Scene sceneOf({
  String id = 'scene-1',
  String chapterId = 'chapter-1',
  String documentId = 'document-1',
}) => Scene(
  id: SceneId(id),
  chapterId: ChapterId(chapterId),
  documentId: DocumentId(documentId),
  title: 'La falaise',
  order: OrderKey('5'),
  wordCount: 12,
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: DateTime.now(),
);

/// A server that records the operations it receives.
final class RecordingTransport implements SyncTransport {
  /// The operations the server received.
  final List<SyncOp> pushed = <SyncOp>[];

  @override
  Future<PushResult> push(List<SyncOp> ops) async {
    pushed.addAll(ops);
    return PushResult(
      accepted: List<SyncOp>.unmodifiable(ops),
      duplicated: const <SyncOp>[],
      rejected: const <RejectedOperation>[],
      lamportAck: 0,
    );
  }

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
