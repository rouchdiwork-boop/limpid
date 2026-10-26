import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/export_repository.dart';
import 'package:limpid_app/src/domain/providers.dart';
import 'package:limpid_app/src/domain/repositories.dart';
import 'package:limpid_app/src/features/export/export_file_saver.dart';

/// Le dépôt des travaux d'export.
///
/// Le dépôt des travaux est le même objet que le dépôt des exports : le
/// premier suit le travail, le second attend le fichier. Un dépôt qui ne
/// sait pas suivre les travaux ne sait pas les demander : l'écran dit
/// alors que l'export est indisponible.
final Provider<ExportJobRepository> exportJobRepositoryProvider =
    Provider<ExportJobRepository>((Ref ref) {
      final ExportRepository repository = ref.watch(exportRepositoryProvider);
      if (repository is ExportJobRepository) return repository;
      return const UnavailableExportJobRepository();
    });

/// L'ecriture du fichier d'un export sur le poste de l'auteur.
///
/// L'ecriture est un port : l'ecran ne sait pas ou le fichier s'ecrit, il
/// sait seulement qu'il doit l'ecrire.
typedef ExportFileWriter = Future<void> Function(ExportArtefact artefact);

/// L'ecriture du fichier, par defaut celle du poste.
final Provider<ExportFileWriter> exportFileWriterProvider =
    Provider<ExportFileWriter>((Ref ref) {
      return (ExportArtefact artefact) {
        return saveExportFile(
          fileName: artefact.fileName,
          mimeType: artefact.mimeType,
          bytes: artefact.bytes,
        );
      };
    });
