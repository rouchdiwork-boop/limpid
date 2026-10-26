import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_sync/limpid_sync.dart';

import 'project_declaration.dart';
import 'project_identity_store.dart';
import 'sync_api_client.dart';

/// The project, as the server knows it.
///
/// The record carries the two states of the publication (D-33): the
/// editorial stage of the manuscript and the visibility of the book in the
/// showcase.
final class RegisteredProject {
  /// Creates a record.
  const RegisteredProject({
    required this.id,
    required this.title,
    required this.synopsis,
    required this.status,
    required this.language,
    required this.isPublic,
  });

  /// Reads the record from the answer of the API.
  ///
  /// The answer of the API is the envelope of the repository: the `data`
  /// field carries the project.
  factory RegisteredProject.fromJson(Map<String, Object?> json) {
    final RegisteredProject project = RegisteredProject(
      id: _text(json, 'id'),
      title: _text(json, 'title'),
      synopsis: _text(json, 'synopsis'),
      status: _statusOf(json, 'status'),
      language: _text(json, 'language'),
      isPublic: _flag(json, 'is_public'),
    );
    if (project.id.isEmpty) {
      throw const SyncTransportException(
        'The server did not return the identifier of the project.',
        code: 'sync_invalid_payload',
      );
    }
    return project;
  }

  /// The identifier of the project on the server.
  final String id;

  /// The title of the manuscript.
  final String title;

  /// The synopsis of the manuscript.
  final String synopsis;

  /// The editorial stage of the manuscript.
  final ManuscriptStatus status;

  /// The language of the manuscript, as a BCP 47 tag.
  final String language;

  /// Whether the book is in the showcase of the server.
  final bool isPublic;

  /// Reads a column of text, an empty string when it is missing.
  static String _text(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    return value is String ? value : '';
  }

  /// Reads a column holding a flag, `false` when it is missing.
  static bool _flag(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is bool) return value;
    if (value is int) return value != 0;
    return false;
  }

  /// Reads a column holding an editorial stage.
  static ManuscriptStatus _statusOf(Map<String, Object?> json, String field) {
    final String name = _text(json, field);
    for (final ManuscriptStatus status in ManuscriptStatus.values) {
      if (status.name == name) return status;
    }
    return ManuscriptStatus.draft;
  }
}

/// The registration of the local projects on the server.
///
/// The server refuses the operations of a project it does not know: the
/// registry therefore **declares** the project before its operations
/// travel.
///
/// ## The rule of the identifier
///
/// The server mints the identifier of a project: the registry sends the
/// identifier the device knows, and the server may answer with another one.
/// The device then adopts it (see [ProjectIdentityStore.adopt]) and the two
/// sides end up with the same identifier — the one the showcase of the book
/// is built on.
///
/// ## The idempotence
///
/// The registration never creates a project twice: the registry asks the
/// server whether it already knows the project, and reuses the answer of the
/// server when it does. A second synchronisation of the same book therefore
/// never produces a second project on the server.
final class ServerProjectRegistry {
  /// Creates a registry.
  const ServerProjectRegistry({required this.api, required this.identities});

  /// The client of the API.
  final SyncApiClient api;

  /// The identity of the projects on the device.
  final ProjectIdentityStore identities;

  /// Declares the local project [projectId] on the server.
  ///
  /// The call is idempotent: a project the server already knows is not
  /// created twice, and the answer of the server is reused.
  ///
  /// The call throws a [SyncException] when the server refuses the
  /// declaration: the operations of the project stay in the durable queue
  /// of the device, and the failure is reported to the author.
  Future<RegisteredProject> register(String projectId) async {
    final ProjectDeclaration? declaration = await identities.read(projectId);
    if (declaration == null) {
      throw SyncTransportException(
        'The project $projectId is unknown on the device.',
        code: 'sync_unknown_project',
      );
    }
    final RegisteredProject? known = await _find(projectId);
    if (known != null) {
      await _align(known, declaration);
      return known;
    }
    final RegisteredProject created = await _create(declaration);
    if (created.id != projectId) {
      await identities.adopt(projectId: projectId, serverProjectId: created.id);
    }
    await _align(created, declaration);
    return created;
  }

  /// The project the server knows, `null` when it knows none.
  ///
  /// The answer is the answer of the server: the registry never guesses
  /// what the server knows about a project.
  Future<RegisteredProject?> _find(String projectId) async {
    final Map<String, String> headers = await api.headers();
    final http.Response? response = await api.sendOptional(
      () => api.client.get(
        api.uri('/v1/projects/${Uri.encodeComponent(projectId)}'),
        headers: headers,
      ),
    );
    if (response == null) return null;
    return RegisteredProject.fromJson(api.decodeObject(response.body));
  }

  /// Creates the project on the server.
  ///
  /// The server may refuse the creation because the project already exists
  /// — another device of the author created it in the meantime. The answer
  /// of the server is then reused: the project is never created twice.
  Future<RegisteredProject> _create(ProjectDeclaration declaration) async {
    final Map<String, String> headers = await api.headers();
    final String body = jsonEncode(<String, Object?>{
      'id': declaration.id,
      'title': declaration.title,
      'synopsis': declaration.synopsis,
      'language': declaration.language,
      'status': declaration.status.name,
    });
    try {
      final http.Response response = await api.send(
        () => api.client.post(
          api.uri('/v1/projects'),
          headers: headers,
          body: body,
        ),
      );
      return RegisteredProject.fromJson(api.decodeObject(response.body));
    } on SyncTransportException catch (error) {
      if (error.statusCode != 409) rethrow;
      final RegisteredProject? existing = await _find(declaration.id);
      if (existing == null) rethrow;
      return existing;
    }
  }

  /// Writes the two states of the publication on the server.
  ///
  /// The stage and the visibility are the only fields the registry writes
  /// after the creation: the title and the synopsis travel with the
  /// creation, and the title of a book is not part of the CRDT — the last
  /// device that synchronises would silently overwrite the others.
  Future<void> _align(
    RegisteredProject server,
    ProjectDeclaration declaration,
  ) async {
    final Map<String, Object?> changes = <String, Object?>{};
    if (server.status != declaration.status) {
      changes['status'] = declaration.status.name;
    }
    if (server.isPublic != declaration.isPublic) {
      changes['is_public'] = declaration.isPublic;
    }
    if (changes.isEmpty) return;
    await _update(server.id, changes);
  }

  /// Sends the changes to the server.
  Future<void> _update(String projectId, Map<String, Object?> changes) async {
    final Map<String, String> headers = await api.headers();
    await api.send(
      () => api.client.patch(
        api.uri('/v1/projects/${Uri.encodeComponent(projectId)}'),
        headers: headers,
        body: jsonEncode(changes),
      ),
    );
  }
}
