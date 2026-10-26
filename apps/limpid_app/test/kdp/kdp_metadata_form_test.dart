import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/kdp_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/features/publication/kdp/kdp_metadata_form.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

import '../data/support.dart';
import '../features/publication/fakes.dart';
import 'fakes.dart';

/// Le titre du livre du test.
const String bookTitle = 'Les Heures de Cendre';

/// L'ordre des champs de texte du formulaire.
const int _titleIndex = 0;
const int _subtitleIndex = 1;
const int _authorIndex = 2;
const int _isbnIndex = 7;

void main() {
  group('le formulaire des métadonnées', () {
    testWidgets('refuse un ISBN manquant avant d’envoyer', (tester) async {
      final FakeKdpRepository repository = FakeKdpRepository();
      await tester.pumpWidget(
        _formHarness(repository: repository, books: _books()),
      );
      await tester.pumpAndSettle();
      final AppLocalizations strings = _strings(tester);

      await _fillTitleAndAuthor(tester);
      await _submit(tester, strings);

      // Le champ fautif est nommé : l'erreur est portée par le champ ISBN.
      expect(_errorTextOf(tester), contains(strings.kdpIsbn));
      // Rien n'est parti : le dossier n'a pas été préparé.
      expect(repository.prepared, isEmpty);
    });

    testWidgets('refuse un ISBN mal formé avant d’envoyer', (tester) async {
      final FakeKdpRepository repository = FakeKdpRepository();
      await tester.pumpWidget(
        _formHarness(repository: repository, books: _books()),
      );
      await tester.pumpAndSettle();
      final AppLocalizations strings = _strings(tester);

      await _fillTitleAndAuthor(tester);
      await tester.enterText(_fieldAt(tester, _isbnIndex), '1234567890');
      await _submit(tester, strings);

      expect(_errorTextOf(tester), contains(strings.kdpIsbn));
      expect(repository.prepared, isEmpty);
    });

    testWidgets('prépare le dossier avec des métadonnées valides', (
      tester,
    ) async {
      final FakeKdpRepository repository = FakeKdpRepository();
      await tester.pumpWidget(
        _formHarness(repository: repository, books: _books()),
      );
      await tester.pumpAndSettle();
      final AppLocalizations strings = _strings(tester);

      await _fillTitleAndAuthor(tester);
      await tester.enterText(_fieldAt(tester, _isbnIndex), '9782364123458');
      await _submit(tester, strings);

      expect(repository.prepared, hasLength(1));
      final KdpMetadata metadata = repository.prepared.first;
      expect(metadata.title, bookTitle);
      expect(metadata.author, 'Camille Martin');
      expect(metadata.isbn, '9782364123458');
      expect(repository.preparedProjects, <String>['project-1']);
    });

    testWidgets('le sous-titre est joint au titre', (tester) async {
      final FakeKdpRepository repository = FakeKdpRepository();
      await tester.pumpWidget(
        _formHarness(repository: repository, books: _books()),
      );
      await tester.pumpAndSettle();
      final AppLocalizations strings = _strings(tester);

      await _fillTitleAndAuthor(tester);
      await tester.enterText(
        _fieldAt(tester, _subtitleIndex),
        'Le premier jour',
      );
      await tester.enterText(_fieldAt(tester, _isbnIndex), '9782364123458');
      await _submit(tester, strings);

      expect(
        repository.prepared.first.composedTitle,
        '$bookTitle: Le premier jour',
      );
    });
  });
}

/// Les livres que le test propose.
List<Project> _books() => <Project>[
  projectOf(id: 'project-1', title: bookTitle),
];

/// Le champ de texte numéro [index].
Finder _fieldAt(WidgetTester tester, int index) =>
    find.byType(TextField).at(index);

/// Le message d'erreur du premier champ fautif.
String? _errorTextOf(WidgetTester tester) {
  for (final TextField field in tester.widgetList<TextField>(
    find.byType(TextField),
  )) {
    final String? error = field.decoration?.errorText;
    if (error != null) return error;
  }
  return null;
}

/// Les chaînes du formulaire.
AppLocalizations _strings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(KdpMetadataForm)));

/// Appuie sur le bouton qui prépare le dossier.
///
/// Le formulaire est plus long que l'écran du test : le bouton est amené
/// dans la vue avant d'être pressé.
Future<void> _submit(WidgetTester tester, AppLocalizations strings) async {
  final Finder button = find.text(strings.kdpPrepare);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Remplit le titre et l'auteur, et choisit le livre.
Future<void> _fillTitleAndAuthor(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(bookTitle).last);
  await tester.pumpAndSettle();

  await tester.enterText(_fieldAt(tester, _titleIndex), bookTitle);
  await tester.enterText(_fieldAt(tester, _authorIndex), 'Camille Martin');
  await tester.pumpAndSettle();
}

/// Le formulaire du test.
Widget _formHarness({
  required FakeKdpRepository repository,
  required List<Project> books,
}) {
  return ProviderScope(
    overrides: [
      kdpRepositoryProvider.overrideWithValue(repository),
      manuscriptRepositoryProvider.overrideWithValue(
        FakePublicationRepository(projects: books),
      ),
    ],
    child: MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: KdpMetadataForm(
            onSubmit: (KdpMetadata metadata, String projectId) async {
              await repository.prepare(
                projectId: projectId,
                metadata: metadata,
              );
            },
          ),
        ),
      ),
    ),
  );
}
