import 'package:limpid_app/src/auth/auth_runtime.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// The account that owns the local data of the device.
///
/// ## One device, several accounts
///
/// The local database is unique per device and outlives the session: two
/// accounts that use the same machine share the same file. The scope names
/// the account the local data belongs to, so that the data of one account is
/// never served to another.
///
/// The scope is **resolved on every read and every write**: it follows the
/// session, and a change of account takes effect at once — without reopening
/// the database and without moving the file. The manuscripts of an account
/// stay where they are: the author who comes back finds them again.
///
/// ## The two scopes
///
/// The scope of the account partitions the **storage** of the device: the
/// preferences, the index of the documents, the cursors of the
/// synchronisation, the queue of the operations and the snapshots of the
/// documents. The manuscripts keep their own scope — the owner of the
/// project — because a book can be shared with a collaborator.
final class LocalAccountScope {
  /// Creates a scope resolving the account with [resolve].
  const LocalAccountScope(this._resolve);

  /// The scope of the account whose session is open on the device.
  ///
  /// The session is read **live**: the account of the scope changes as soon
  /// as the author signs in or out.
  factory LocalAccountScope.live() => const LocalAccountScope(_liveAccountId);

  /// The identifier of the account that owns the local data right now.
  String get accountId => _resolve();

  final String Function() _resolve;
}

/// The identifier of the account whose session is open on the device.
///
/// The session of the demonstration mode is the one the bootstrap restored:
/// the demonstration always belongs to the same local author. The session of
/// Supabase is read live: the account changes as soon as the author signs in
/// or out.
String _liveAccountId() {
  final AuthRuntime runtime = AuthRuntimeHolder.current;
  return switch (runtime) {
    SupabaseAuthRuntime(:final client) =>
      client.auth.currentSession?.user.id ?? kLocalAuthorId,
    DemoAuthRuntime(:final session) => session?.userId ?? kLocalAuthorId,
  };
}
