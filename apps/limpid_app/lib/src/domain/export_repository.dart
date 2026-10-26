import 'dart:typed_data';

import 'package:limpid_core/limpid_core.dart';

import 'providers.dart';

/// The file produced by an export.
final class ExportArtefact {
  /// Creates an artefact.
  const ExportArtefact({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  /// The recommended name of the file, extension included.
  final String fileName;

  /// The media type of the file.
  final String mimeType;

  /// The content of the file.
  final Uint8List bytes;
}

/// The exports of a manuscript.
///
/// The generation happens on the server: `POST /v1/export/<format>` creates
/// a **job**, and the server prepares the book in the background. The
/// legacy call waits for the file and hands it back; the screens that
/// follow the work use [ExportJobRepository] instead.
abstract interface class ExportRepository {
  /// Exports the manuscript and returns the produced file.
  ///
  /// Throws a typed error when the server refuses the export — a manuscript
  /// with no content yet, an unknown format, a missing right.
  Future<ExportArtefact> export({
    required String projectId,
    required ExportFormat format,
  });
}

/// L'état d'un travail d'export, vu par l'interface.
///
/// Le travail est un **événement** : il attend le serveur, il court, il
/// réussit ou il échoue. Il n'est jamais rejoué : une relance crée un
/// travail neuf.
sealed class ExportProgress {
  /// Crée un état.
  const ExportProgress();

  /// L'identifiant du travail.
  String get id;
}

/// Le travail attend le serveur.
final class ExportQueued extends ExportProgress {
  /// Crée un état.
  const ExportQueued(this.id);

  @override
  /// L'identifiant du travail.
  final String id;
}

/// Le serveur fabrique l'artefact.
final class ExportRunning extends ExportProgress {
  /// Crée un état.
  const ExportRunning(this.id);

  @override
  /// L'identifiant du travail.
  final String id;
}

/// L'artefact est prêt : il est téléchargeable jusqu'à son expiration.
final class ExportReady extends ExportProgress {
  /// Crée un état.
  const ExportReady({
    required this.id,
    required this.downloadUrl,
    required this.expiresAt,
    this.fileName,
  });

  @override
  /// L'identifiant du travail.
  final String id;

  /// L'adresse signée du fichier produit.
  ///
  /// L'adresse porte sa propre expiration : elle cesse de servir le
  /// fichier quand l'artefact expire.
  final Uri downloadUrl;

  /// L'instant où le fichier disparaît, `null` quand le serveur ne le
  /// dit pas.
  final DateTime? expiresAt;

  /// Le nom du fichier produit.
  final String? fileName;
}

/// La fabrication a échoué : le travail peut être relancé.
final class ExportFailed extends ExportProgress {
  /// Crée un état.
  const ExportFailed({required this.id, required this.message});

  @override
  /// L'identifiant du travail.
  final String id;

  /// Le message de l'échec, écrit par le serveur.
  final String message;
}

/// Le dépôt des travaux d'export.
///
/// Le dépôt demande le travail, le suit, et le relance. Le serveur
/// fabrique le livre : l'application attend son fichier, elle ne le
/// fabrique jamais.
abstract interface class ExportJobRepository implements ExportRepository {
  /// Demande l'export du livre [projectId] dans le format [format].
  ///
  /// La demande rend un travail en attente : l'artefact n'est pas prêt.
  Future<ExportProgress> start({
    required String projectId,
    required ExportFormat format,
  });

  /// L'état du travail [jobId].
  Future<ExportProgress> read(String jobId);

  /// Relance le travail [jobId].
  ///
  /// La relance crée un travail **neuf** : le travail en échec reste un
  /// événement, il n'est pas rejoué.
  Future<ExportProgress> retry(String jobId);

  /// Le fichier du travail prêt [ready].
  ///
  /// Le fichier est binaire : il ne peut pas passer par le presse-papiers,
  /// et il se donne tel quel au navigateur ou au système de fichiers.
  Future<ExportArtefact> download(ExportReady ready);

  @override
  Future<ExportArtefact> export({
    required String projectId,
    required ExportFormat format,
  });
}

/// Le dépôt des travaux d'un build qui ne sait pas les suivre.
///
/// L'export demande un service distant : quand il n'y en a pas, l'écran
/// dit que l'export est indisponible, plutôt que de promettre un fichier
/// que le serveur n'a jamais produit.
final class UnavailableExportJobRepository implements ExportJobRepository {
  /// Crée le dépôt.
  const UnavailableExportJobRepository();

  @override
  Future<ExportProgress> start({
    required String projectId,
    required ExportFormat format,
  }) async {
    throw const ServiceUnavailableException();
  }

  @override
  Future<ExportProgress> read(String jobId) async {
    throw const ServiceUnavailableException();
  }

  @override
  Future<ExportProgress> retry(String jobId) async {
    throw const ServiceUnavailableException();
  }

  @override
  Future<ExportArtefact> download(ExportReady ready) async {
    throw const ServiceUnavailableException();
  }

  @override
  Future<ExportArtefact> export({
    required String projectId,
    required ExportFormat format,
  }) async {
    throw const ServiceUnavailableException();
  }
}
