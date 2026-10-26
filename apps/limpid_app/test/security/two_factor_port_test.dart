import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/two_factor_repository.dart';

void main() {
  group('UnavailableTwoFactorRepository', () {
    const UnavailableTwoFactorRepository repository =
        UnavailableTwoFactorRepository();

    test('refuse de lire l’état du compte', () async {
      await expectLater(
        repository.status(),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse d’inscrire le compte', () async {
      await expectLater(
        repository.enroll(),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de confirmer l’inscription', () async {
      await expectLater(
        repository.confirm(code: '123456'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de vérifier un code', () async {
      await expectLater(
        repository.verify(code: '123456'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuse de désactiver le second facteur', () async {
      await expectLater(
        repository.disable(),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('se déclare comme un service indisponible', () {
      expect(repository, isA<UnavailableService>());
    });
  });

  group('twoFactorRepositoryProvider', () {
    test('vaut la doublure indisponible par défaut', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(twoFactorRepositoryProvider),
        isA<UnavailableTwoFactorRepository>(),
      );
    });
  });

  group('TwoFactorStatus', () {
    test('exige l’activation quand la formule l’exige', () {
      expect(fakeRequired.needsActivation, isTrue);
      expect(fakeRequired.isOptional, isFalse);
    });

    test('n’exige plus rien quand le second facteur est actif', () {
      expect(fakeEnabled.needsActivation, isFalse);
    });
  });
}

/// A state whose plan requires the second factor.
const TwoFactorStatus fakeRequired = TwoFactorStatus(
  enrolled: false,
  enabled: false,
  required: true,
);

/// A state whose second factor is on.
const TwoFactorStatus fakeEnabled = TwoFactorStatus(
  enrolled: true,
  enabled: true,
  required: false,
);
