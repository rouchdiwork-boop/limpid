import 'dart:io';

import 'package:limpid_core/limpid_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/comment_store.dart';
import '../db/project_record.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../services/access_control.dart';

/// Registers the routes of the discussions.
///
/// The routes read and write the discussions of a project. The caller must
/// be the owner of the project or one of its collaborators: the check is the
/// one of [AccessControl], the server never trusts the client.
void registerCommentRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config, {
  required CommentStore comments,
}) {
  router.get('/v1/projects/<projectId>/threads', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    await AccessControl.requireProject(dependencies.projects, projectId, auth);

    final List<StoredThread> threads = await comments.listThreads(
      projectId: projectId,
    );
    return ApiResponse.ok(threads.map(_threadJson).toList(growable: false));
  });

  router.post('/v1/projects/<projectId>/threads', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    final ProjectAccess access = await AccessControl.requireProject(
      dependencies.projects,
      projectId,
      auth,
    );
    if (!canComment(access.role)) {
      throw const ForbiddenException(
        message: 'Votre rôle sur ce projet ne permet pas de commenter.',
      );
    }

    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    final CommentThread thread = _threadOf(body);
    await _requireKnownAuthors(comments, projectId, thread);

    final StoredThread stored = await comments.saveThread(
      projectId: projectId,
      thread: thread,
      excerpt:
          body.optionalString('excerpt', maxLength: maxCommentExcerptLength) ??
          '',
    );
    return ApiResponse.ok(_threadJson(stored), status: HttpStatus.created);
  });

  router.get('/v1/projects/<projectId>/members', (
    Request request,
    String projectId,
  ) async {
    final AuthContext auth = requireAuthContext(request);
    await AccessControl.requireProject(dependencies.projects, projectId, auth);

    final List<CommentMember> members = await comments.listMembers(
      projectId: projectId,
    );
    return ApiResponse.ok(members.map(_memberJson).toList(growable: false));
  });
}

/// Refuses the messages attributed to an account outside the project.
Future<void> _requireKnownAuthors(
  CommentStore comments,
  String projectId,
  CommentThread thread,
) async {
  if (thread.comments.isEmpty) return;
  final List<CommentMember> members = await comments.listMembers(
    projectId: projectId,
  );
  final Set<String> known = members
      .map((CommentMember member) => member.userId)
      .toSet();
  for (final Comment comment in thread.comments) {
    if (known.contains(comment.author.value)) continue;
    throw const ValidationException(
      field: 'comments',
      message:
          'Un message est attribué à un compte qui ne collabore pas au projet.',
    );
  }
}

/// Reads a discussion from the body of the request.
CommentThread _threadOf(JsonBody body) {
  final String threadId = body.requireString(
    'id',
    maxLength: maxCommentIdLength,
  );
  return CommentThread(
    id: CommentId(threadId),
    markId: MarkId(
      body.requireString('mark_id', maxLength: maxCommentIdLength),
    ),
    comments: _commentsOf(body, threadId),
    isResolved: body.optionalBool('is_resolved') ?? false,
    resolvedAt: _dateOf(body, 'resolved_at'),
  );
}

/// Reads the messages of a discussion from the body of the request.
List<Comment> _commentsOf(JsonBody body, String threadId) {
  final List<dynamic> raw = body.requireList(
    'comments',
    maxLength: maxCommentsPerThread,
  );
  final List<Comment> comments = <Comment>[];
  for (final dynamic entry in raw) {
    if (entry is! Map<String, dynamic>) {
      throw const ValidationException(
        field: 'comments',
        message: 'Chaque message doit être un objet JSON.',
      );
    }
    comments.add(_commentOf(JsonBody(entry), threadId));
  }
  return List<Comment>.unmodifiable(comments);
}

/// Reads a message from its JSON object.
///
/// The discussion of the message is the one of the request: a client never
/// attaches a message to another discussion.
Comment _commentOf(JsonBody body, String threadId) {
  return Comment(
    id: CommentId(body.requireString('id', maxLength: maxCommentIdLength)),
    threadId: CommentId(threadId),
    author: AuthorId(
      body.requireString('author_id', maxLength: maxCommentIdLength),
    ),
    body: body.requireString('body', maxLength: maxCommentBodyLength),
    createdAt: _dateOf(body, 'created_at') ?? DateTime.now().toUtc(),
    editedAt: _dateOf(body, 'edited_at'),
  );
}

/// Reads a date of the body, `null` when it is absent.
DateTime? _dateOf(JsonBody body, String field) {
  final String? raw = body.optionalString(field);
  if (raw == null) return null;
  final DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw ValidationException(
      field: field,
      message: 'Le champ « $field » doit valoir une date ISO 8601.',
    );
  }
  return parsed.toUtc();
}

/// The JSON of a discussion.
Map<String, Object?> _threadJson(StoredThread stored) {
  final CommentThread thread = stored.thread;
  return <String, Object?>{
    'id': thread.id.value,
    'mark_id': thread.markId.value,
    'excerpt': stored.excerpt,
    'is_resolved': thread.isResolved,
    'resolved_at': _isoOf(thread.resolvedAt),
    'created_at': stored.createdAt.toUtc().toIso8601String(),
    'updated_at': stored.updatedAt.toUtc().toIso8601String(),
    'comments': thread.comments.map(_commentJson).toList(growable: false),
  };
}

/// The JSON of a message.
Map<String, Object?> _commentJson(Comment comment) {
  return <String, Object?>{
    'id': comment.id.value,
    'thread_id': comment.threadId.value,
    'author_id': comment.author.value,
    'body': comment.body,
    'created_at': comment.createdAt.toUtc().toIso8601String(),
    'edited_at': _isoOf(comment.editedAt),
  };
}

/// The JSON of a collaborator.
Map<String, Object?> _memberJson(CommentMember member) {
  return <String, Object?>{
    'user_id': member.userId,
    'display_name': member.displayName,
    'role': member.role.name,
  };
}

/// The ISO 8601 form of a date, `null` when it is absent.
String? _isoOf(DateTime? value) => value?.toUtc().toIso8601String();
