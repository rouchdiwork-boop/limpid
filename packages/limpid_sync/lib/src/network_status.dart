import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:limpid_sync/src/transport/auth_token_provider.dart';

/// Detects whether the device can reach the API.
///
/// The probe is injectable so the application can plug its own connectivity
/// information (the `connectivity_plus` plugin on mobile, for instance) and
/// so the tests can simulate an offline device without any network.
abstract interface class ConnectivityProbe {
  /// Whether the API is reachable right now.
  ///
  /// The implementation must never throw: an unreachable network is a
  /// `false` answer, not an error.
  Future<bool> isOnline();
}

/// The default [ConnectivityProbe]: it pings the API.
///
/// Any HTTP answer — including an error status — proves that the network
/// works, so only a transport failure is reported as offline.
final class HttpConnectivityProbe implements ConnectivityProbe {
  /// Creates a probe.
  HttpConnectivityProbe({
    required this.baseUrl,
    required this.client,
    this.tokenProvider,
    this.timeout = const Duration(seconds: 5),
    this.closeInjectedClient = false,
  });

  /// The root of the API, used to build the ping URL.
  final Uri baseUrl;

  /// Resolves the bearer token sent with the ping.
  final AuthTokenProvider? tokenProvider;

  /// The timeout of the ping.
  final Duration timeout;

  /// Whether [dispose] closes the injected HTTP client.
  final bool closeInjectedClient;

  /// The HTTP client used to ping the API.
  ///
  /// It is injected so the tests can replace the network with a fake.
  final http.Client client;

  @override
  Future<bool> isOnline() async {
    try {
      final token = await tokenProvider?.call();
      final headers = <String, String>{'accept': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['authorization'] = 'Bearer $token';
      }
      await client.get(baseUrl, headers: headers).timeout(timeout);
      return true;
    } on Object {
      return false;
    }
  }

  /// Releases the resources held by the probe.
  void dispose() {
    if (closeInjectedClient) client.close();
  }
}
