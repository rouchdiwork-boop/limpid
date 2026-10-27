/// Le consentement de l'auteur à l'envoi de son texte chez un tiers (D-08).
///
/// Le consentement est une **décision de l'auteur**, pas une case cochée
/// par l'application : il est posé par l'écran des réglages, et
/// **enregistré** par le serveur, avec la date.
///
/// Deux mots le décrivent : le *périmètre* dit ce qui est autorisé
/// (aujourd'hui, l'envoi du texte à un tiers), le *fournisseur* dit à qui.
/// Un compte qui change de fournisseur n'a pas donné son accord pour le
/// nouveau : le consentement se pose donc pour un couple
/// (périmètre, fournisseur).
library;

/// Le périmètre de l'envoi du texte de l'auteur à un fournisseur tiers.
const String aiConsentScopeTextToThirdParty = 'text_to_third_party';

/// Les fournisseurs que le service connaît.
abstract final class AiConsentProviders {
  /// Le fournisseur d'hébergement : le texte part de la machine du
  /// serveur, et le serveur l'envoie à un tiers.
  static const String anthropic = 'anthropic';

  /// Le fournisseur local : le modèle tourne sur la machine de l'auteur,
  /// et le texte n'en sort pas.
  static const String ollama = 'ollama';

  /// Les fournisseurs dont le texte **ne quitte pas** la machine de
  /// l'auteur.
  ///
  /// Un compte qui travaille en mode local n'a pas besoin du consentement :
  /// le texte ne part pas chez un tiers. C'est le contrepoint du
  /// consentement, et l'un des deux suffit.
  static const Set<String> local = <String>{ollama};
}

/// L'état du consentement d'un compte, pour un périmètre et un fournisseur.
///
/// La ligne existe dès que l'auteur a donné son accord une fois : après un
/// retrait, elle porte la date du dernier accord et la date du retrait. Le
/// journal d'audit, lui, garde toute l'histoire des décisions.
final class AiConsentRecord {
  /// Crée un état de consentement.
  const AiConsentRecord({
    required this.userId,
    required this.scope,
    required this.provider,
    required this.isGranted,
    required this.grantedAt,
    this.revokedAt,
  });

  /// Le compte qui a décidé.
  final String userId;

  /// Ce qui est autorisé, par exemple `text_to_third_party`.
  final String scope;

  /// Le fournisseur visé par la décision.
  final String provider;

  /// Indique si l'accord est vivant.
  final bool isGranted;

  /// L'instant du dernier accord donné.
  final DateTime grantedAt;

  /// L'instant du retrait, `null` quand l'accord est vivant.
  final DateTime? revokedAt;
}

/// Le port de persistance des consentements.
///
/// Le port ne porte aucune règle métier : la lecture de l'état, la pose de
/// l'accord et sa trace vivent dans le service.
abstract interface class AiConsentStore {
  /// Le consentement du compte [userId] pour le périmètre [scope] et le
  /// fournisseur [provider], `null` quand l'auteur n'a jamais décidé.
  Future<AiConsentRecord?> find({
    required String userId,
    required String scope,
    required String provider,
  });

  /// Enregistre l'état du consentement.
  ///
  /// L'écriture remplace l'état précédent : un accord redonné après un
  /// retrait repart d'une date d'accord nouvelle, et le journal d'audit
  /// garde l'histoire.
  Future<void> save(AiConsentRecord record);
}
