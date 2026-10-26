import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:limpid_app/src/auth/auth_repository.dart';
import 'package:path_provider/path_provider.dart';

/// The name of the file that holds the local session.
const String localAuthFileName = 'limpid_local_auth.json';

/// The state persisted by the demonstration mode.
///
/// The state is small — an identifier and a session — and is read once, when
/// the application starts. A plain file is enough: it needs no schema, no
/// migration and no engine.
@immutable
class LocalAuthState {
  /// Creates the state.
  const LocalAuthState({required this.authorId, this.session});

  /// The identifier of the local author.
  ///
  /// It never changes on a device: the demonstration session always belongs
  /// to the same author.
  final String authorId;

  /// The session of the author, `null` when nobody is signed in.
  final AuthSession? session;

  /// Reads the state from its JSON representation.
  ///
  /// The result is `null` when the representation is not a state: a corrupted
  /// file must not prevent the application from starting.
  static LocalAuthState? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final authorId = json['authorId'];
    if (authorId is! String || authorId.isEmpty) return null;
    final session = json['session'];
    return LocalAuthState(
      authorId: authorId,
      session: session is Map<String, dynamic>
          ? _sessionFromJson(session)
          : null,
    );
  }

  /// The JSON representation of the state.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'authorId': authorId,
    'session': session == null ? null : _sessionToJson(session!),
  };

  static AuthSession? _sessionFromJson(Map<String, dynamic> json) {
    final userId = json['userId'];
    final email = json['email'];
    if (userId is! String || email is! String) return null;
    final authorName = json['authorName'];
    return AuthSession(
      userId: userId,
      email: email,
      authorName: authorName is String ? authorName : null,
    );
  }

  static Map<String, dynamic> _sessionToJson(AuthSession session) =>
      <String, dynamic>{
        'userId': session.userId,
        'email': session.email,
        'authorName': session.authorName,
      };
}

/// Persists the state of the demonstration mode.
abstract interface class LocalAuthStore {
  /// Reads the persisted state, `null` when nothing is persisted.
  Future<LocalAuthState?> read();

  /// Writes the state.
  Future<void> write(LocalAuthState state);
}

/// A store that keeps the state in a JSON file.
///
/// The file lives in the support directory of the application: it survives
/// the restarts and is removed when the application is uninstalled.
final class FileLocalAuthStore implements LocalAuthStore {
  /// Creates the store on top of [file].
  const FileLocalAuthStore(this._file);

  /// Opens the store in the support directory of the application.
  static Future<FileLocalAuthStore> open() async {
    final directory = await getApplicationSupportDirectory();
    return FileLocalAuthStore(File('${directory.path}/$localAuthFileName'));
  }

  final File _file;

  @override
  Future<LocalAuthState?> read() async {
    final String content;
    try {
      content = await _file.readAsString();
    } on FileSystemException {
      // The application runs for the first time: there is no file yet.
      return null;
    }
    if (content.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (error) {
      debugPrint('Le fichier de session locale est illisible : $error');
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    return LocalAuthState.fromJson(decoded);
  }

  @override
  Future<void> write(LocalAuthState state) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(state.toJson()), flush: true);
  }
}

/// A store that keeps the state in memory.
///
/// The store is used by the tests and when the application cannot reach the
/// file system.
final class InMemoryLocalAuthStore implements LocalAuthStore {
  /// Creates the store.
  InMemoryLocalAuthStore();

  LocalAuthState? _state;

  @override
  Future<LocalAuthState?> read() async => _state;

  @override
  Future<void> write(LocalAuthState state) async {
    _state = state;
  }
}
