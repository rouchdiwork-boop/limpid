import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_routes.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_submission_screen.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import 'fakes.dart';
import 'harness.dart';

void main() {
  group("l'écran des dépôts", () {
    testWidgets('liste les dépôts du compte avec leur état', (tester) async {
      useSurface(tester, const Size(1200, 900));
      final FakeKdpRepository repository = FakeKdpRepository(
        submissions: <KdpSubmission>[fakeSubmission, fakeRefusedSubmission],
      );

      await tester.pumpWidget(kdpHarness(repository: repository));
      await tester.pumpAndSettle();

      final AppLocalizations strings = kdpStrings(tester);

      expect(find.text('Les Heures de Cendre'), findsNWidgets(2));
      expect(find.text(strings.kdpStateDraft), findsOneWidget);
      expect(find.text(strings.kdpStateRefused), findsOneWidget);
    });

    testWidgets('montre l’état vide quand il n’y a aucun dépôt', (
      tester,
    ) async {
      useSurface(tester, const Size(1200, 900));
      final FakeKdpRepository repository = FakeKdpRepository(
        submissions: <KdpSubmission>[],
      );

      await tester.pumpWidget(kdpHarness(repository: repository));
      await tester.pumpAndSettle();

      final AppLocalizations strings = kdpStrings(tester);

      expect(find.text(strings.kdpEmpty), findsOneWidget);
      // L'action de préparer un dépôt est proposée deux fois : dans la
      // barre de la page et dans l'état vide.
      expect(find.text(strings.kdpCreate), findsWidgets);
    });

    testWidgets('ouvre le dépôt que l’auteur choisit', (tester) async {
      useSurface(tester, const Size(1200, 900));
      final FakeKdpRepository repository = FakeKdpRepository();

      await tester.pumpWidget(kdpHarness(repository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Les Heures de Cendre').first);
      await tester.pumpAndSettle();

      final AppLocalizations strings = submissionStrings(tester);

      expect(find.byType(KdpSubmissionScreen), findsOneWidget);
      // Le dossier est ouvert : l'action de dépôt est là.
      expect(find.text(strings.kdpSubmit), findsOneWidget);
    });

    testWidgets('dit que le service n’est pas configuré', (tester) async {
      useSurface(tester, const Size(1200, 900));
      final FakeKdpRepository repository = FakeKdpRepository()
        ..error = const ServiceUnavailableException();

      await tester.pumpWidget(kdpHarness(repository: repository));
      await tester.pumpAndSettle();

      final AppLocalizations strings = kdpStrings(tester);

      expect(find.text(strings.kdpNotConfigured), findsOneWidget);
    });
  });

  group("l'écran d'un dépôt", () {
    testWidgets('montre le motif du refus d’Amazon', (tester) async {
      useSurface(tester, const Size(1200, 900));
      final FakeKdpRepository repository = FakeKdpRepository(
        submissions: <KdpSubmission>[fakeRefusedSubmission],
      );

      await tester.pumpWidget(
        kdpHarness(
          repository: repository,
          location: KdpRoutes.submission('pub_2'),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = submissionStrings(tester);

      expect(find.text(strings.kdpRefused), findsOneWidget);
      expect(find.text(strings.kdpRefusedReason), findsOneWidget);
      // Le motif d'Amazon est montré tel quel : l'auteur sait quoi corriger.
      expect(
        find.text("L'ISBN indiqué est déjà utilisé par un autre ouvrage."),
        findsOneWidget,
      );
      // L'action de corriger et réessayer est là.
      expect(find.text(strings.kdpFixAndRetry), findsOneWidget);
    });

    testWidgets('dépose le dossier chez Amazon', (tester) async {
      useSurface(tester, const Size(1200, 900));
      final FakeKdpRepository repository = FakeKdpRepository();

      await tester.pumpWidget(
        kdpHarness(
          repository: repository,
          location: KdpRoutes.submission('pub_1'),
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations strings = submissionStrings(tester);

      await tester.ensureVisible(find.text(strings.kdpSubmit));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.kdpSubmit));
      await tester.pumpAndSettle();

      expect(repository.deposited, <String>['pub_1']);
      expect(find.text(strings.kdpStateSubmitted), findsOneWidget);
    });

    testWidgets(
      'dit que le dépôt est impossible sur ce poste sans dire que le livre '
      'est arrivé',
      (tester) async {
        useSurface(tester, const Size(1200, 900));
        final FakeKdpRepository repository = FakeKdpRepository()
          ..depositError = const KdpUnavailableException(
            reason: "La distribution Amazon KDP n'est pas configurée.",
          );

        await tester.pumpWidget(
          kdpHarness(
            repository: repository,
            location: KdpRoutes.submission('pub_1'),
          ),
        );
        await tester.pumpAndSettle();

        final AppLocalizations strings = submissionStrings(tester);

        await tester.ensureVisible(find.text(strings.kdpSubmit));
        await tester.pumpAndSettle();
        await tester.tap(find.text(strings.kdpSubmit));
        await tester.pumpAndSettle();

        expect(find.text(strings.kdpNotConfigured), findsOneWidget);
        // Le dossier n'est pas parti : l'écran ne le dit pas déposé.
        expect(find.text(strings.kdpStateSubmitted), findsNothing);
        expect(find.text(strings.kdpStateDraft), findsOneWidget);
      },
    );

    testWidgets('la liste garde l’état du dépôt de la session', (tester) async {
      useSurface(tester, const Size(1200, 900));
      final FakeKdpRepository repository = FakeKdpRepository();

      await tester.pumpWidget(
        kdpHarness(
          repository: repository,
          location: KdpRoutes.submission('pub_1'),
        ),
      );
      await tester.pumpAndSettle();
      final AppLocalizations strings = submissionStrings(tester);

      await tester.ensureVisible(find.text(strings.kdpSubmit));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.kdpSubmit));
      await tester.pumpAndSettle();

      // Le retour à la liste montre l'état qu'Amazon a donné, pas celui
      // d'une préparation.
      await tester.tap(find.byIcon(LimpidIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.text(strings.kdpStateSubmitted), findsOneWidget);
      expect(find.text(strings.kdpStateDraft), findsNothing);
    });

    testWidgets('montre les problèmes du contrôle de soumission', (
      tester,
    ) async {
      useSurface(tester, const Size(1200, 900));
      final FakeKdpRepository repository = FakeKdpRepository(
        submissions: <KdpSubmission>[fakeBlockedSubmission],
      );

      await tester.pumpWidget(
        kdpHarness(
          repository: repository,
          location: KdpRoutes.submission('pub_3'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          "L'édition imprimée exige un ISBN : ajoutez-le avant de déposer le "
          'dossier sur Amazon.',
        ),
        findsOneWidget,
      );
    });
  });
}
