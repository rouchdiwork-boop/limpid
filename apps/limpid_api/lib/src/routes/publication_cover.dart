import 'dart:convert';

import 'package:limpid_export/limpid_export.dart';
import 'package:shelf/shelf.dart';

import '../db/kdp_database.dart';
import '../db/kdp_record.dart';
import '../db/project_record.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';

/// The route of the cover of a public book.
///
/// The cover is an **artefact**: the export engine produces it, exactly as
/// it produces the cover of the exported book. The route serves it to a
/// reader who has no account, like the page of the book serves it.
const String publicBookCoverRoute = '/v1/public/books/<projectId>/cover';

/// The address of the cover of the book [projectId].
///
/// The address is **relative**: the public answer never carries a bare
/// storage address, and the reader follows the book it belongs to.
String publicCoverUrlOf(String projectId) {
  return '/v1/public/books/${Uri.encodeComponent(projectId)}/cover';
}

/// The media type of the cover.
const String publicCoverMediaType = 'image/svg+xml; charset=utf-8';

/// Serves the cover of the public book [projectId].
///
/// The three refusals — unknown book, unpublished book, private book —
/// answer the very same `404`: the showcase must never disclose the
/// existence of a book the visitor may not read.
Future<Response> servePublicCover(
  AppDependencies dependencies,
  String projectId,
) async {
  final ProjectRecord? project = await dependencies.projects.findPublic(
    projectId: projectId,
  );
  if (project == null) {
    throw const NotFoundException();
  }
  final String cover = await publicCoverSvgOf(dependencies, project);
  return Response.ok(
    cover,
    headers: <String, String>{
      'content-type': publicCoverMediaType,
      'cache-control': 'public, max-age=3600',
    },
  );
}

/// The cover of the book [project], as an SVG document.
///
/// The generator is deterministic: the same book always yields the same
/// cover. The cover does not carry the text of the manuscript — only its
/// title, its subtitle and its author — so the manuscript is never read to
/// draw it.
Future<String> publicCoverSvgOf(
  AppDependencies dependencies,
  ProjectRecord project,
) async {
  final KdpDatabase? kdp = dependencies.kdp;
  final KdpPublication? publication = kdp == null
      ? null
      : await kdp.findPublicationByProject(projectId: project.id);
  final String? author = _text(publication?.author);
  final ExportBook book = ExportBook(
    title: project.title,
    authors: author == null ? const <String>[] : <String>[author],
    language: project.language,
    metadata: ExportMetadata(
      isbn: _text(publication?.isbn),
      description: project.synopsis.isEmpty ? null : project.synopsis,
      language: project.language,
      // The identifier of the project is the seed of the colour of the
      // cover: it is the very value the application hashes, so a book keeps
      // the same colour in the studio and in its exported cover.
      identifier: project.id,
    ),
    // La couverture ne montre pas le manuscrit : le livre de l'export a
    // pourtant au moins un chapitre, et il n'en montre aucun.
    chapters: const <ExportChapter>[
      ExportChapter(title: '', blocks: <ExportBlock>[]),
    ],
  );
  final ExportResult cover = await generateCover(book);
  return utf8.decode(cover.bytes);
}

/// The value [value] cleaned, `null` when it holds nothing.
String? _text(String? value) {
  if (value == null) return null;
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
