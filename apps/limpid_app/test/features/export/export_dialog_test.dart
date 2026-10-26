import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/l10n/generated/app_localizations.dart';
import 'package:limpid_app/src/domain/export_repository.dart';
import 'package:limpid_app/src/features/export/export_dialog.dart';
import 'package:limpid_app/src/features/export/export_providers.dart';
import 'package:limpid_core/limpid_core.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

void main() {
  group('fenêtre d’export', () {
    testWidgets('demande le travail et suit son avancement', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository();
      await tester.pumpWidget(_harness(repository));
      final AppLocalizations strings = _strings(tester);

      expect(find.text(strings.exportTitle), findsOneWidget);
      expect(find.text(strings.exportStart), findsOneWidget);

      await tester.tap(find.text(strings.exportStart));
      await tester.pump();

      expect(repository.started, 1);
      expect(find.text(strings.exportRunning), findsOneWidget);

      // Le travail aboutit : la fenêtre le dit et propose le fichier.
      repository.finish();
      await tester.pump(const Duration(seconds: 2));

      expect(find.text(strings.exportReady), findsOneWidget);
      expect(find.text(strings.exportDownload), findsOneWidget);
    });

    testWidgets('propose la relance quand le travail échoue', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository();
      await tester.pumpWidget(_harness(repository));
      final AppLocalizations strings = _strings(tester);

      await tester.tap(find.text(strings.exportStart));
      await tester.pump();

      repository.fail();
      await tester.pump(const Duration(seconds: 2));

      expect(find.text(strings.exportFailed), findsOneWidget);
      expect(find.text(strings.actionRetry), findsOneWidget);

      await tester.tap(find.text(strings.actionRetry));
      await tester.pump();

      // La relance crée un travail **neuf**.
      expect(repository.retried, 1);
      expect(find.text(strings.exportRunning), findsOneWidget);
    });

    testWidgets('télécharge le fichier quand l’auteur le demande', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository();
      ExportArtefact? written;
      await tester.pumpWidget(
        _harness(
          repository,
          writer: (ExportArtefact artefact) async {
            written = artefact;
          },
        ),
      );
      final AppLocalizations strings = _strings(tester);

      await tester.tap(find.text(strings.exportStart));
      await tester.pump();
      repository.finish();
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.text(strings.exportDownload));
      await tester.pump();

      expect(written, isNotNull);
      expect(written!.fileName, 'le-livre.epub');
    });
  });
}

/// Le fichier ecrit sur le poste.
Widget _harness(_FakeRepository repository, {ExportFileWriter? writer}) {
  return ProviderScope(
    overrides: [
      exportJobRepositoryProvider.overrideWithValue(repository),
      if (writer != null) exportFileWriterProvider.overrideWithValue(writer),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('fr'),
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      home: const Scaffold(body: ExportDialog(projectId: 'project-1')),
    ),
  );
}

/// Les chaines de l'interface.
AppLocalizations _strings(WidgetTester tester) {
  final BuildContext context = tester.element(find.byType(ExportDialog));
  return AppLocalizations.of(context);
}

/// Un dépôt de travaux qui repond comme le serveur.
final class _FakeRepository implements ExportJobRepository {
  /// Le nombre de demandes de travail.
  int started = 0;

  /// Le nombre de relances.
  int retried = 0;

  ExportProgress _progress = const ExportQueued('job-1');

  @override
  Future<ExportProgress> start({
    required String projectId,
    required ExportFormat format,
  }) async {
    started++;
    _progress = const ExportQueued('job-1');
    return _progress;
  }

  @override
  Future<ExportProgress> read(String jobId) async => _progress;

  @override
  Future<ExportProgress> retry(String jobId) async {
    retried++;
    _progress = const ExportRunning('job-2');
    return _progress;
  }

  @override
  Future<ExportArtefact> download(ExportReady ready) async {
    return ExportArtefact(
      fileName: 'le-livre.epub',
      mimeType: 'application/epub+zip',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );
  }

  @override
  Future<ExportArtefact> export({
    required String projectId,
    required ExportFormat format,
  }) async {
    throw UnimplementedError();
  }

  /// Le travail aboutit.
  void finish() {
    _progress = ExportReady(
      id: 'job-1',
      downloadUrl: Uri.parse('https://storage.test/le-livre.epub'),
      expiresAt: null,
      fileName: 'le-livre.epub',
    );
  }

  /// Le travail echoue.
  void fail() {
    _progress = const ExportFailed(id: 'job-1', message: 'Le livre est vide.');
  }
}
