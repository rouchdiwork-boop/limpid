/// La double authentification de l'auteur.
///
/// Le contrat vit dans la couche domaine : l'écran de sécurité le nomme,
/// l'implémentation de la couche données le réalise — aucun des deux ne
/// connaît l'autre. Les types qu'il manipule sont **immuables** : l'écran
/// lit un état, il ne le modifie jamais.
///
/// Le secret et les codes de récupération sont **secrets** : le serveur ne
/// les rend qu'une fois, l'application ne les écrit jamais sur le disque.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// Le moyen par lequel un code a été accepté.
enum TwoFactorMethod {
  /// Un code à six chiffres, calculé par l'application d'authentification.
  totp,

  /// Un code de récupération, à usage unique.
  recovery;

  /// Le moyen de nom [key], `null` quand le nom est inconnu.
  ///
  /// Un nom inconnu ne fait jamais échouer la lecture : l'écran montre alors
  /// le moyen le plus prudent, le code à six chiffres.
  static TwoFactorMethod? fromKey(String key) {
    for (final TwoFactorMethod method in TwoFactorMethod.values) {
      if (method.name == key) return method;
    }
    return null;
  }
}

/// L'état de la double authentification d'un compte.
///
/// Les trois figures viennent de la route `GET /v1/me/2fa` : elles disent ce
/// que le compte a fait, jamais ce que le serveur a refusé.
final class TwoFactorStatus {
  /// Crée un état.
  const TwoFactorStatus({
    required this.enrolled,
    required this.enabled,
    required this.required,
  });

  /// Indique que le compte a un secret enregistré.
  ///
  /// Un compte inscrit mais pas encore confirmé a un secret que le serveur
  /// n'accepte pas encore.
  final bool enrolled;

  /// Indique que la double authentification est active.
  final bool enabled;

  /// Indique que la formule du compte exige la double authentification.
  final bool required;

  /// Indique que la formule exige un second facteur que le compte n'a pas
  /// encore activé.
  bool get needsActivation => required && !enabled;

  /// Indique que la formule n'exige rien : le compte choisit.
  bool get isOptional => !required;
}

/// L'inscription d'un compte dans la double authentification.
///
/// Le secret est rendu **une seule fois**, au moment de l'inscription :
/// l'application le montre, elle ne le garde pas.
final class TwoFactorEnrollment {
  /// Crée une inscription.
  const TwoFactorEnrollment({
    required this.secret,
    required this.otpauthUrl,
    required this.digits,
    required this.periodSeconds,
  });

  /// Le secret partagé, encodé en base32.
  final String secret;

  /// L'adresse d'inscription de l'application d'authentification.
  ///
  /// Elle porte le secret : la montrer, c'est déjà le partager. L'écran ne
  /// l'affiche que le temps de l'inscription.
  final String otpauthUrl;

  /// Le nombre de chiffres des codes.
  final int digits;

  /// La durée d'un pas de l'horloge, en secondes.
  final int periodSeconds;
}

/// La preuve du second facteur, portée par les requêtes de l'application.
///
/// La preuve est un jeton court : elle expire, et l'application en demande
/// une nouvelle quand il vient à bout. Elle vit dans la **session**, jamais
/// sur le disque.
final class TwoFactorProof {
  /// Crée une preuve.
  const TwoFactorProof({
    required this.proof,
    required this.expiresAt,
    required this.method,
  });

  /// Le jeton à envoyer dans l'en-tête de la requête.
  final String proof;

  /// L'instant où la preuve cesse d'être valable.
  final DateTime expiresAt;

  /// Le moyen qui a produit la preuve.
  final TwoFactorMethod method;

  /// Indique si la preuve a expiré à l'instant [now].
  ///
  /// Une preuve expirée ne part jamais sur une requête : le serveur la
  /// refuserait, et l'auteur devrait ressaisir son code.
  bool isExpiredAt(DateTime now) => !now.toUtc().isBefore(expiresAt.toUtc());
}

/// Le port de la double authentification.
///
/// L'écran de sécurité lit ce port et n'atteint jamais le serveur. La
/// doublure par défaut refuse les appels et dit pourquoi : un écran ne
/// présente jamais une double authentification qu'il n'a pas lue.
abstract interface class TwoFactorRepository {
  /// L'état de la double authentification du compte.
  ///
  /// Lève une erreur typée quand le serveur refuse la lecture ou ne peut
  /// pas être atteint.
  Future<TwoFactorStatus> status();

  /// Inscrit le compte dans la double authentification.
  ///
  /// Le secret rendu n'est actif qu'après la confirmation d'un premier
  /// code : une inscription n'enferme jamais l'auteur hors de son compte.
  Future<TwoFactorEnrollment> enroll();

  /// Confirme l'inscription avec le premier [code] de l'auteur.
  ///
  /// Renvoie les codes de récupération, **une seule fois** : le serveur ne
  /// les rend plus jamais.
  Future<List<String>> confirm({required String code});

  /// Vérifie un [code] de second facteur et rend la preuve.
  ///
  /// Le code est un code à six chiffres ou un code de récupération. La
  /// preuve est valable jusqu'à son expiration.
  Future<TwoFactorProof> verify({required String code});

  /// Désactive la double authentification du compte.
  ///
  /// Le secret est effacé et les codes de récupération sont invalidés.
  Future<void> disable();
}

/// Une [TwoFactorRepository] qui ne peut pas atteindre le serveur.
///
/// La démonstration mode n'a pas de service distant : l'écran de sécurité
/// le dit au lieu de prétendre que la double authentification est active.
final class UnavailableTwoFactorRepository
    implements TwoFactorRepository, UnavailableService {
  /// Crée le dépôt indisponible.
  const UnavailableTwoFactorRepository();

  @override
  Future<TwoFactorStatus> status() async =>
      throw const ServiceUnavailableException();

  @override
  Future<TwoFactorEnrollment> enroll() async =>
      throw const ServiceUnavailableException();

  @override
  Future<List<String>> confirm({required String code}) async =>
      throw const ServiceUnavailableException();

  @override
  Future<TwoFactorProof> verify({required String code}) async =>
      throw const ServiceUnavailableException();

  @override
  Future<void> disable() async => throw const ServiceUnavailableException();
}

/// Le dépôt de la double authentification.
///
/// Le point de composition le remplace par l'implémentation de la couche
/// données. Le défaut refuse les appels et dit pourquoi : un écran ne
/// présente jamais une double authentification qu'il n'a pas lue.
final Provider<TwoFactorRepository> twoFactorRepositoryProvider =
    Provider<TwoFactorRepository>(
      (Ref ref) => const UnavailableTwoFactorRepository(),
    );
