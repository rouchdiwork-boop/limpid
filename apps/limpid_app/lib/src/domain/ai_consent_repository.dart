import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// L'état du consentement de l'auteur à l'envoi de son texte chez un tiers.
///
/// D-08 : le texte de l'auteur ne part chez un fournisseur qu'après un
/// accord explicite. L'état dit ce que le compte a décidé, et le
/// fournisseur que la décision concerne.
@immutable
class AiConsentState {
  /// Crée un état.
  const AiConsentState({
    required this.scope,
    required this.provider,
    required this.isGranted,
    required this.requiresConsent,
    this.grantedAt,
    this.revokedAt,
  });

  /// Le périmètre de la décision : l'envoi du texte à un tiers.
  final String scope;

  /// Le fournisseur que la décision concerne.
  final String provider;

  /// L'auteur a-t-il donné son accord ?
  final bool isGranted;

  /// L'accord est-il nécessaire ?
  ///
  /// Un fournisseur qui tourne sur la machine de l author's n'en a pas
  /// besoin : rien ne quitte le poste.
  final bool requiresConsent;

  /// L'instant de l'accord, `null` quand il n'y en a pas eu.
  final DateTime? grantedAt;

  /// L'instant du retrait, `null` quand l'accord tient.
  final DateTime? revokedAt;

  /// L'état lu quand le service n'est pas configuré.
  static const AiConsentState unavailable = AiConsentState(
    scope: 'text_to_third_party',
    provider: 'anthropic',
    isGranted: false,
    requiresConsent: false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiConsentState &&
          other.scope == scope &&
          other.provider == provider &&
          other.isGranted == isGranted &&
          other.requiresConsent == requiresConsent &&
          other.grantedAt == grantedAt &&
          other.revokedAt == revokedAt);

  @override
  int get hashCode => Object.hash(
    scope,
    provider,
    isGranted,
    requiresConsent,
    grantedAt,
    revokedAt,
  );
}

/// Le port du consentement à l'envoi du texte chez un tiers.
///
/// Le port est celui de l'API : la décision de l'auteur est **la sienne**,
/// elle vit sur le serveur, et l'appareil la lit.
abstract interface class AiConsentRepository {
  /// L'état du consentement du compte.
  Future<AiConsentState> state();

  /// Donne l'accord de l'auteur.
  Future<AiConsentState> grant();

  /// Retire l'accord de l'auteur.
  Future<AiConsentState> revoke();
}

/// Un dépôt qui ne peut pas atteindre le serveur.
///
/// L'accord est alors **retiré** : l'assistant n'envoie rien, et l'écran
/// dit pourquoi.
final class UnavailableAiConsentRepository implements AiConsentRepository {
  /// Crée le dépôt.
  const UnavailableAiConsentRepository();

  @override
  Future<AiConsentState> state() async => AiConsentState.unavailable;

  @override
  Future<AiConsentState> grant() async {
    throw const ServiceUnavailableException();
  }

  @override
  Future<AiConsentState> revoke() async => AiConsentState.unavailable;
}

/// Le dépôt du consentement, au sens de la racine de composition.
///
/// La composition racine remplace ce port par l'implémentation qui lit
/// l'API ; le défaut retire l'accord, jamais l'inverse.
final Provider<AiConsentRepository> aiConsentRepositoryProvider =
    Provider<AiConsentRepository>((Ref ref) {
      return const UnavailableAiConsentRepository();
    });
