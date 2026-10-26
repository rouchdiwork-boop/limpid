import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';

import 'fakes.dart';

void main() {
  group('le port de publication', () {
    test('refuse quand le service n’est pas configuré', () async {
      const UnavailableKdpRepository repository = UnavailableKdpRepository();

      await expectLater(
        repository.list(),
        throwsA(isA<ServiceUnavailableException>()),
      );
      await expectLater(
        repository.find('pub_1'),
        throwsA(isA<ServiceUnavailableException>()),
      );
      await expectLater(
        repository.prepare(projectId: 'project_1', metadata: fakeMetadata),
        throwsA(isA<ServiceUnavailableException>()),
      );
      await expectLater(
        repository.deposit(submissionId: 'pub_1'),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('la doublure dit qu’elle n’a aucun service', () {
      const UnavailableKdpRepository repository = UnavailableKdpRepository();

      expect(repository, isA<UnavailableService>());
    });
  });

  group('la validation des métadonnées', () {
    test('accepte un ISBN valide', () {
      expect(fakeMetadata.validate(), isNull);
    });

    test('refuse un ISBN manquant', () {
      final KdpMetadata metadata = fakeMetadata.copyWith(isbn: '');

      final KdpFieldError? error = metadata.validate();

      expect(error, isNotNull);
      expect(error?.field, KdpFields.isbn);
      expect(error?.reason, KdpFieldErrorReason.empty);
    });

    test('refuse un ISBN mal formé', () {
      final KdpMetadata metadata = fakeMetadata.copyWith(isbn: '1234567890');

      final KdpFieldError? error = metadata.validate();

      expect(error, isNotNull);
      expect(error?.field, KdpFields.isbn);
      expect(error?.reason, KdpFieldErrorReason.malformedIsbn);
    });

    test('refuse un titre vide', () {
      final KdpMetadata metadata = fakeMetadata.copyWith(title: '   ');

      final KdpFieldError? error = metadata.validate();

      expect(error?.field, KdpFields.title);
      expect(error?.reason, KdpFieldErrorReason.empty);
    });

    test('refuse un auteur vide', () {
      final KdpMetadata metadata = fakeMetadata.copyWith(author: '');

      final KdpFieldError? error = metadata.validate();

      expect(error?.field, KdpFields.author);
    });

    test('lit un ISBN de dix chiffres', () {
      final KdpMetadata metadata = fakeMetadata.copyWith(isbn: '123456789X');

      expect(metadata.validate(), isNull);
    });

    test('normalise l’ISBN : ni tiret ni espace', () {
      final KdpMetadata metadata = fakeMetadata.copyWith(
        isbn: '978-2-3641-2345-8',
      );

      expect(metadata.normalizedIsbn, fakeIsbn);
      expect(metadata.validate(), isNull);
    });

    test('joint le sous-titre au titre', () {
      final KdpMetadata metadata = fakeMetadata.copyWith(
        subtitle: 'Le premier jour',
      );

      expect(metadata.composedTitle, 'Les Heures de Cendre: Le premier jour');
    });
  });

  group('la trace d’un dépôt', () {
    test('un dépôt accepté ne part jamais deux fois', () {
      final KdpSubmission submission = fakeSubmission.copyWith(
        state: KdpState.submitted,
      );

      expect(submission.canDeposit, isFalse);
    });

    test('un dossier bloqué ne part pas', () {
      final KdpSubmission submission = fakeBlockedSubmission;

      expect(submission.canDeposit, isFalse);
      expect(submission.blockingIssues, hasLength(1));
    });

    test('un dossier prêt part', () {
      expect(fakeSubmission.canDeposit, isTrue);
    });

    test('un refus porte son motif', () {
      expect(fakeRefusedSubmission.refusal, isNotNull);
      expect(fakeRefusedSubmission.refusal?.issues, hasLength(1));
      expect(
        fakeRefusedSubmission.refusal?.issues.first.message,
        contains('ISBN'),
      );
    });
  });
}
