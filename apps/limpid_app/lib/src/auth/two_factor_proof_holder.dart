import 'package:limpid_app/src/domain/two_factor_repository.dart';

/// Le détenteur de la preuve du second facteur.
///
/// ## Pourquoi une cellule et pas un provider
///
/// Le client qui parle à l'API est construit **avant** le premier cadre,
/// et la requête qu'il signe doit porter la preuve que l'écran a obtenue
/// un moment plus tôt. Le `ProviderScope` n'existe pas encore à ce moment :
/// la preuve est donc tenue dans une cellule que l'écran écrit et que le
/// client lit — le même motif que `AuthRuntimeHolder`.
///
/// La preuve appartient à la **session** : elle est lâchée quand la
/// session se ferme, et une preuve expirée n'est jamais envoyée.
abstract final class TwoFactorProofHolder {
  static TwoFactorProof? _current;

  /// The clock used to tell whether the proof is still valid.
  static DateTime Function() _clock = DateTime.now;

  /// The current proof, `null` when there is none.
  ///
  /// An expired proof is **not** returned: it is forgotten, so that a
  /// request is never signed with a proof the server would reject.
  static TwoFactorProof? get current {
    final TwoFactorProof? proof = _current;
    if (proof == null) return null;
    if (proof.isExpiredAt(_clock())) {
      _current = null;
      return null;
    }
    return proof;
  }

  /// The value of the current proof, `null` when there is none.
  ///
  /// This is what the API client reads to sign a request.
  static String? get currentValue => current?.proof;

  /// Sets the proof of the session.
  static void set(TwoFactorProof proof) {
    _current = proof;
  }

  /// Forgets the proof of the session.
  ///
  /// The call is idempotent: forgetting a proof that is not there is not
  /// an error.
  static void clear() {
    _current = null;
  }

  /// Replaces the clock used to read the expiry.
  ///
  /// The tests make the time pass without waiting.
  static void useClock(DateTime Function() clock) {
    _clock = clock;
  }

  /// Restores the default clock and forgets the proof.
  static void reset() {
    _clock = DateTime.now;
    _current = null;
  }
}
