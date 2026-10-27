import 'package:limpid_api/src/db/ai_consent_store.dart';
import 'package:test/test.dart';

/// Les consentements sous test.
final class AiConsentFixture {
  /// Crée un cas.
  const AiConsentFixture({required this.consents, required this.dispose});

  /// Le magasin des consentements.
  final AiConsentStore consents;

  /// Libère les ressources du cas.
  final Future<void> Function() dispose;
}

/// Exécute le contrat du port [AiConsentStore].
///
/// Les mêmes scénarios tournent contre le magasin en mémoire et contre le
/// magasin SQLite : l'égalité des deux exécutions est la preuve que la base
/// de développement se comporte comme l'implémentation de référence.
void runAiConsentStoreContract({
  required String name,
  required Future<AiConsentFixture> Function() build,
}) {
  group('contrat des consentements — $name', () {
    late AiConsentFixture fixture;

    setUp(() async {
      fixture = await build();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('ne rend pas un consentement inconnu', () async {
      expect(
        await fixture.consents.find(
          userId: 'user-1',
          scope: aiConsentScopeTextToThirdParty,
          provider: 'anthropic',
        ),
        isNull,
      );
    });

    test('enregistre un consentement et le relit', () async {
      await fixture.consents.save(_granted());

      final AiConsentRecord? stored = await fixture.consents.find(
        userId: 'user-1',
        scope: aiConsentScopeTextToThirdParty,
        provider: 'anthropic',
      );

      expect(stored, isNotNull);
      expect(stored!.userId, 'user-1');
      expect(stored.scope, aiConsentScopeTextToThirdParty);
      expect(stored.provider, 'anthropic');
      expect(stored.isGranted, isTrue);
      expect(stored.grantedAt, _moment);
      expect(stored.revokedAt, isNull);
    });

    test('l\'écriture remplace l\'état précédent', () async {
      await fixture.consents.save(_granted());
      await fixture.consents.save(
        AiConsentRecord(
          userId: 'user-1',
          scope: aiConsentScopeTextToThirdParty,
          provider: 'anthropic',
          isGranted: false,
          grantedAt: _moment,
          revokedAt: _moment.add(const Duration(hours: 1)),
        ),
      );

      final AiConsentRecord? stored = await fixture.consents.find(
        userId: 'user-1',
        scope: aiConsentScopeTextToThirdParty,
        provider: 'anthropic',
      );

      expect(stored, isNotNull);
      expect(stored!.isGranted, isFalse);
      expect(stored.grantedAt, _moment);
      expect(stored.revokedAt, _moment.add(const Duration(hours: 1)));
    });

    test('ne mélange pas les comptes', () async {
      await fixture.consents.save(_granted());

      final AiConsentRecord? other = await fixture.consents.find(
        userId: 'user-2',
        scope: aiConsentScopeTextToThirdParty,
        provider: 'anthropic',
      );

      expect(other, isNull);
    });

    test('ne mélange pas les fournisseurs', () async {
      await fixture.consents.save(_granted());

      final AiConsentRecord? other = await fixture.consents.find(
        userId: 'user-1',
        scope: aiConsentScopeTextToThirdParty,
        provider: 'ollama',
      );

      expect(other, isNull);
    });

    test('ne mélange pas les périmètres', () async {
      await fixture.consents.save(_granted());

      final AiConsentRecord? other = await fixture.consents.find(
        userId: 'user-1',
        scope: 'autre_perimetre',
        provider: 'anthropic',
      );

      expect(other, isNull);
    });
  });
}

/// L'instant de référence des consentements de la suite.
final DateTime _moment = DateTime.utc(2026, 10, 26, 9);

/// Un consentement accordé de la suite.
AiConsentRecord _granted() {
  return AiConsentRecord(
    userId: 'user-1',
    scope: aiConsentScopeTextToThirdParty,
    provider: 'anthropic',
    isGranted: true,
    grantedAt: _moment,
  );
}
