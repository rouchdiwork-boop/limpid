import 'ai_consent_store.dart';

/// L'implémentation en mémoire du port [AiConsentStore].
///
/// Le magasin garde le même invariant que les implémentations SQL : une
/// seule ligne par couple (compte, périmètre, fournisseur), et l'écriture
/// remplace l'état précédent.
final class InMemoryAiConsentStore implements AiConsentStore {
  /// Crée un port vide.
  InMemoryAiConsentStore();

  /// Les consentements, par clé.
  final Map<String, AiConsentRecord> _records = <String, AiConsentRecord>{};

  @override
  Future<AiConsentRecord?> find({
    required String userId,
    required String scope,
    required String provider,
  }) async {
    return _records[_key(userId: userId, scope: scope, provider: provider)];
  }

  @override
  Future<void> save(AiConsentRecord record) async {
    _records[_key(
          userId: record.userId,
          scope: record.scope,
          provider: record.provider,
        )] =
        record;
  }

  /// La clé d'un consentement.
  ///
  /// La clé est jointe par un caractère qui ne peut pas figurer dans un
  /// identifiant de compte ni dans un nom de fournisseur : deux consentements
  /// différents ne peuvent pas tomber dans la même case.
  static String _key({
    required String userId,
    required String scope,
    required String provider,
  }) {
    return '$userId\u0000$scope\u0000$provider';
  }
}
