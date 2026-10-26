import '../errors/app_exception.dart';

/// The deletion of an account from the authentication service.
///
/// Les comptes vivent dans Supabase Auth, pas dans la base de l'API : la
/// purge d'un compte doit l'effacer là-bas aussi, sinon l'auteur peut
/// encore se connecter après la purge, et le compte n'a pas disparu.
abstract interface class AccountAuthDeletion {
  /// Whether the authentication service is configured.
  ///
  /// Un service qui n'est pas configuré ne porte aucun compte : il n'y a
  /// rien à effacer, et la purge n'est pas bloquée par son absence.
  bool get isConfigured;

  /// Erases the account [userId] from the authentication service.
  ///
  /// The call is idempotent: an account that is already gone is not an
  /// error, the purge simply has nothing left to do there.
  ///
  /// The method throws when the service refuses the call or is unreachable:
  /// the purge is then incomplete, and the next pass tries again.
  Future<void> deleteAccount({required String userId});
}

/// An [AccountAuthDeletion] standing for an authentication service that is
/// not configured.
final class UnavailableAccountAuthDeletion implements AccountAuthDeletion {
  /// Creates the deletion.
  const UnavailableAccountAuthDeletion();

  @override
  bool get isConfigured => false;

  @override
  Future<void> deleteAccount({required String userId}) {
    throw const ServiceUnavailableException(
      message:
          "Le service d'authentification n'est pas configuré sur ce poste.",
    );
  }
}
