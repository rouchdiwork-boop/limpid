/// Provides the bearer token used to authenticate the requests sent to the
/// API.
///
/// The token is resolved for every request: it can expire while the client
/// is running, and the application is free to rotate it. Returning `null`
/// means "no credentials", the transport then sends an anonymous request.
typedef AuthTokenProvider = Future<String?> Function();
