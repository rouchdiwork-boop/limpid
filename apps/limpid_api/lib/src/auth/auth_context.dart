/// The authenticated caller of a request.
///
/// The context is immutable: it is created by the JWT verifier and never
/// modified afterwards.
final class AuthContext {
  /// Creates an authentication context.
  const AuthContext({
    required this.userId,
    required this.email,
    required this.claims,
  });

  /// The identifier of the authenticated account.
  final String userId;

  /// The email address of the authenticated account, empty when unknown.
  final String email;

  /// The claims of the verified token.
  final Map<String, dynamic> claims;

  /// The value of a string claim, `null` when it is absent.
  String? stringClaim(String name) {
    final Object? value = claims[name];
    return value is String ? value : null;
  }

  /// The value of a boolean claim, `null` when it is absent.
  bool? boolClaim(String name) {
    final Object? value = claims[name];
    return value is bool ? value : null;
  }

  @override
  String toString() => 'AuthContext($userId)';
}
