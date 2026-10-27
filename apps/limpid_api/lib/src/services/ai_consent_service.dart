import '../db/ai_consent_store.dart';
import '../errors/app_exception.dart';

/// L'état du consentement d'un compte, tel que l'écran des réglages le voit.
///
/// L'état ne porte **aucun texte** de l'auteur : il dit si le compte a
/// autorisé l'envoi de son texte à un tiers, et quand.
final class AiConsentState {
  /// Crée un état.
  const AiConsentState({
    required this.scope,
    required this.provider,
    required this.isGranted,
    required this.requiresConsent,
    this.grantedAt,
    this.revokedAt,
  });

  /// Ce qui est autorisé, par exemple `text_to_third_party`.
  final String scope;

  /// Le fournisseur visé par la décision.
  final String provider;

  /// Indique si l'accord de l'auteur est vivant.
  final bool isGranted;

  /// Indique si ce fournisseur demande un accord.
  ///
  /// Un fournisseur local ne demande rien : le texte ne quitte pas la
  /// machine de l'auteur.
  final bool requiresConsent;

  /// L'instant du dernier accord donné.
  final DateTime? grantedAt;

  /// L'instant du retrait, `null` quand l'accord est vivant.
  final DateTime? revokedAt;

  /// La représentation JSON de l'état.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'scope': scope,
      'provider': provider,
      'is_granted': isGranted,
      'requires_consent': requiresConsent,
      'granted_at': grantedAt?.toUtc().toIso8601String(),
      'revoked_at': revokedAt?.toUtc().toIso8601String(),
    };
  }
}

/// Le service du consentement à l'envoi du texte chez un tiers (D-08).
///
/// Le service lit l'état, pose l'accord de l'auteur et le retire. Il ne
/// connaît ni la route, ni la formule du compte : il répond à une question
/// simple — ce compte a-t-il autorisé l'envoi de son texte à ce
/// fournisseur ?
///
/// Le service porte aussi le fournisseur du serveur : c'est la seule source
/// de vérité, et l'accord de l'auteur vaut pour ce fournisseur-là, pas pour
/// un autre.
///
/// La **trace** des décisions est écrite par la route, qui tient la requête
/// et son adresse : le journal d'audit garde ainsi le même visage partout.
final class AiConsentService {
  /// Crée un service sur le magasin [store].
  AiConsentService({
    required this.store,
    this.provider = AiConsentProviders.anthropic,
    Set<String>? localProviders,
    DateTime Function()? clock,
  }) : localProviders = localProviders ?? AiConsentProviders.local,
       _clock = clock ?? _utcNow;

  /// Le magasin des consentements.
  final AiConsentStore store;

  /// Le fournisseur que le serveur interroge.
  final String provider;

  /// Les fournisseurs dont le texte ne quitte pas la machine de l'auteur.
  final Set<String> localProviders;

  final DateTime Function() _clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// L'état du consentement du compte [userId].
  ///
  /// Un compte qui n'a jamais décidé a un état simple : l'accord est
  /// refusé, et aucune date n'est inventée.
  Future<AiConsentState> stateOf({required String userId}) async {
    final AiConsentRecord? record = await store.find(
      userId: userId,
      scope: aiConsentScopeTextToThirdParty,
      provider: provider,
    );
    if (record == null) {
      return AiConsentState(
        scope: aiConsentScopeTextToThirdParty,
        provider: provider,
        isGranted: false,
        requiresConsent: requiresConsent(provider),
      );
    }
    return AiConsentState(
      scope: record.scope,
      provider: record.provider,
      isGranted: record.isGranted,
      requiresConsent: requiresConsent(provider),
      grantedAt: record.grantedAt,
      revokedAt: record.revokedAt,
    );
  }

  /// Pose l'accord de l'auteur.
  ///
  /// L'accord est enregistré avec la date. La route en trace la décision
  /// dans le journal d'audit : la trace ne porte aucun texte de l'auteur,
  /// elle dit qui a décidé, de quoi, et pour quel fournisseur.
  Future<AiConsentState> grant({required String userId}) async {
    final DateTime now = _clock().toUtc();
    final AiConsentRecord record = AiConsentRecord(
      userId: userId,
      scope: aiConsentScopeTextToThirdParty,
      provider: provider,
      isGranted: true,
      grantedAt: now,
    );
    await store.save(record);
    return stateOf(userId: userId);
  }

  /// Retire l'accord de l'auteur.
  ///
  /// Le retrait est effectif : dès qu'il est enregistré, plus aucun appel ne
  /// part. La ligne reste, avec la date du retrait : la décision garde sa
  /// trace, et le journal d'audit garde toute l'histoire.
  Future<AiConsentState> revoke({required String userId}) async {
    final DateTime now = _clock().toUtc();
    final AiConsentRecord? existing = await store.find(
      userId: userId,
      scope: aiConsentScopeTextToThirdParty,
      provider: provider,
    );
    final AiConsentRecord record = AiConsentRecord(
      userId: userId,
      scope: aiConsentScopeTextToThirdParty,
      provider: provider,
      isGranted: false,
      grantedAt: existing?.grantedAt ?? now,
      revokedAt: now,
    );
    await store.save(record);
    return stateOf(userId: userId);
  }

  /// Vérifie que le compte [userId] a autorisé l'envoi de son texte.
  ///
  /// Le refus est **avant** l'appel : une demande refusée ne coûte rien au
  /// fournisseur, et rien du texte de l'auteur ne part.
  ///
  /// Un fournisseur local ne demande rien : le texte ne quitte pas la
  /// machine de l'auteur.
  ///
  /// [provider] est le fournisseur que l'appel va vraiment interroger. Il
  /// est celui du service quand la passerelle n'en dit rien.
  Future<void> ensureAllowed({required String userId, String? provider}) async {
    final String target = provider ?? this.provider;
    if (!requiresConsent(target)) return;
    final AiConsentRecord? record = await store.find(
      userId: userId,
      scope: aiConsentScopeTextToThirdParty,
      provider: target,
    );
    if (record != null && record.isGranted) return;
    throw const AiConsentRequiredException();
  }

  /// Indique si le fournisseur [provider] demande un accord de l'auteur.
  bool requiresConsent(String provider) => !localProviders.contains(provider);
}
