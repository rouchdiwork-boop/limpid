import 'dart:io';

import 'package:http/http.dart' as http;

import '../errors/app_exception.dart';
import 'account_auth_deletion.dart';

/// The administration of the accounts of a Supabase project.
///
/// The client calls the administration API of Supabase, the only door that
/// erases an account from Auth. The service role key is read from the
/// environment and never reaches the logs: it grants the full access to the
/// project, and a copy of it in a log file is a copy of it in the wild.
///
/// The call is idempotent: an account that is already gone answers a 404,
/// which the client reads as "nothing left to do" and not as a failure.
final class SupabaseAccountAdmin implements AccountAuthDeletion {
  /// Creates the client.
  ///
  /// [baseUrl] is the URL of the Supabase project, without a trailing
  /// slash. [serviceRoleKey] is the key of the service role, read from the
  /// environment.
  SupabaseAccountAdmin({
    required this.baseUrl,
    required this.serviceRoleKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  /// The URL of the Supabase project.
  final String baseUrl;

  /// The key of the service role of the project.
  final String serviceRoleKey;

  /// The time budget of a call to the administration API.
  final Duration timeout;

  final http.Client _client;

  @override
  bool get isConfigured => true;

  @override
  Future<void> deleteAccount({required String userId}) async {
    final http.Response response;
    try {
      response = await _client
          .delete(_userUri(userId), headers: _headers())
          .timeout(timeout);
    } on Object catch (error) {
      throw ServiceUnavailableException(
        message: "Le service d'authentification est injoignable.",
        details: <String, Object?>{'reason': error.runtimeType.toString()},
      );
    }

    // Un compte déjà effacé n'est pas une erreur : la purge n'a rien à
    // faire de plus là-bas, et elle ne doit pas rester bloquée.
    if (response.statusCode == HttpStatus.notFound) return;

    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.noContent) {
      throw ServiceUnavailableException(
        message:
            "Le service d'authentification a refusé la suppression du "
            'compte.',
        details: <String, Object?>{'status': response.statusCode},
      );
    }
  }

  /// The URL of the administration of [userId].
  Uri _userUri(String userId) {
    final String base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse(
      '$base/auth/v1/admin/users/${Uri.encodeComponent(userId)}',
    );
  }

  /// The headers of a call to the administration API.
  ///
  /// The key of the service role is carried by the headers, never by the
  /// body: the request must not leave a trace in a log of the proxy.
  Map<String, String> _headers() {
    return <String, String>{
      'apikey': serviceRoleKey,
      'authorization': 'Bearer $serviceRoleKey',
      'content-type': 'application/json',
    };
  }
}
