import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_middleware.dart';
import '../config/app_config.dart';
import '../db/audit_entry.dart';
import '../dependencies.dart';
import '../errors/app_exception.dart';
import '../http/api_response.dart';
import '../http/json_body.dart';
import '../middleware/rate_limiter.dart';
import '../services/account_deletion.dart';
import '../services/personal_data_archive.dart';
import '../services/personal_data_export.dart';
import '../storage/artifact_keys.dart';
import '../storage/object_storage.dart';

/// L'action journalée quand un auteur demande l'export de ses données.
const String accountExportRequestedAction = 'account.export_requested';

/// La durée de vie de l'URL signée de l'archive.
///
/// L'archive est une copie personnelle du compte : l'URL qui la porte vit
/// peu de temps, et l'objet qu'elle désigne vit dans le seau privé du
/// service.
const Duration accountExportUrlLifetime = Duration(minutes: 15);

/// Enregistre les routes du compte.
///
/// Les deux routes répondent aux obligations de la RGPD (D-19) : l'export
/// des données personnelles et la suppression du compte. Les deux sont
/// protégées : l'appelant est l'auteur authentifié, et l'export ne porte
/// jamais la session de quelqu'un d'autre.
///
/// L'export ne renvoie pas le fichier dans le corps de la réponse : il
/// dépose l'archive dans le stockage objet et rend une URL signée, pour
/// que la réponse reste bornée même quand l'archive est volumineuse.
void registerAccountRoutes(
  Router router,
  AppDependencies dependencies,
  AppConfig config,
) {
  router.get('/v1/me/export', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final PersonalDataExportService service = PersonalDataExportService(
      projects: dependencies.projects,
      sync: dependencies.sync,
      audit: dependencies.audit,
      quotas: dependencies.quotas,
      twoFactor: dependencies.twoFactor,
      webhooks: dependencies.webhooks,
      teams: dependencies.teams,
    );

    final PersonalDataExport export = await service.build(
      userId: auth.userId,
      email: auth.email,
    );

    final ({List<PersonalDataAsset> embedded, int omitted}) assets =
        await _assetsOf(dependencies.storage, export);
    final PersonalDataArchive archive = PersonalDataArchiveBuilder.build(
      export: export,
      assets: assets.embedded,
      omittedAssets: assets.omitted,
    );

    // L'archive est déposée dans le stockage objet : la réponse reste
    // bornée, et l'auteur télécharge un fichier qu'il ouvre dans un
    // archiveur.
    final String key =
        '${ArtifactKeys.prefixOfAccount(auth.userId)}${archive.fileName}';
    await dependencies.storage.put(
      key: key,
      bytes: archive.bytes,
      contentType: personalDataArchiveMimeType,
    );
    final String url = await dependencies.storage.presignedUrl(
      key: key,
      expires: accountExportUrlLifetime,
    );

    await dependencies.audit.record(
      AuditEntry(
        userId: auth.userId,
        action: accountExportRequestedAction,
        targetType: 'account',
        targetId: auth.userId,
        metadata: archive.counts,
        ip: clientIpOf(request),
      ),
    );

    return ApiResponse.ok(<String, Object?>{
      'format': personalDataArchiveFormat,
      'format_version': personalDataExportFormatVersion,
      'file_name': archive.fileName,
      'mime_type': personalDataArchiveMimeType,
      'storage_key': key,
      'download_url': url,
      'expires_in_seconds': accountExportUrlLifetime.inSeconds,
      'size_bytes': archive.bytes.length,
      'exported_at': export.exportedAt.toUtc().toIso8601String(),
      'counts': archive.counts,
      'manifest': <String, Object?>{
        'path': personalDataManifestName,
        'format_version': personalDataExportFormatVersion,
      },
    });
  });

  router.delete('/v1/me', (Request request) async {
    final AuthContext auth = requireAuthContext(request);
    final JsonBody body = await JsonBody.fromRequest(
      request,
      maxBytes: config.maxBodyBytes,
    );
    if (!body.requireBool('confirm')) {
      throw const ValidationException(
        field: 'confirm',
        message:
            'La suppression du compte doit être confirmée explicitement : '
            'renvoyez « confirm » à true.',
      );
    }

    final AccountDeletionService service = AccountDeletionService(
      audit: dependencies.audit,
    );
    final AccountDeletion deletion = await service.request(
      userId: auth.userId,
      email: auth.email,
      ip: clientIpOf(request),
    );

    return ApiResponse.ok(deletion.toJson());
  });
}

/// Les artefacts du compte, lus dans le stockage objet.
///
/// Seuls les livres que l'auteur **possède** portent des artefacts :
/// l'export d'un livre partagé porte le manuscrit du co-auteur, et ce
/// manuscrit n'est pas la donnée personnelle de l'auteur qui demande
/// l'export.
///
/// Un stockage qui ne sait pas lire donne une archive sans artefact :
/// l'export porte toujours les manuscrits et les réglages.
///
/// La fonction rend aussi le nombre d'artefacts laissés de côté quand les
/// limites de l'export sont atteintes : l'archive le dit, plutôt que de
/// laisser croire que le compte n'avait rien d'autre.
Future<({List<PersonalDataAsset> embedded, int omitted})> _assetsOf(
  ObjectStorage storage,
  PersonalDataExport export,
) async {
  final ObjectStorageReader? reader = switch (storage) {
    final ObjectStorageReader capable => capable,
    _ => null,
  };
  if (reader == null) {
    return (embedded: const <PersonalDataAsset>[], omitted: 0);
  }

  final List<PersonalDataAsset> embedded = <PersonalDataAsset>[];
  var omitted = 0;
  var bytes = 0;
  for (final PersonalDataProject project in export.projects) {
    if (project.scope != personalDataOwnerScope) continue;
    final String prefix = ArtifactKeys.prefixOfProject(project.project.id);
    final List<String> keys = await reader.listKeys(prefix: prefix);
    for (final String key in keys) {
      // Les limites sont vérifiées avant la lecture : un compte qui porte
      // beaucoup d'artefacts ne fait pas relire tout le seau.
      if (embedded.length >= personalDataMaxAssets ||
          bytes >= personalDataMaxAssetBytes) {
        omitted++;
        continue;
      }
      final Uint8List? content = await reader.readObject(key: key);
      if (content == null) continue;
      if (bytes + content.length > personalDataMaxAssetBytes) {
        omitted++;
        continue;
      }
      bytes += content.length;
      embedded.add(
        PersonalDataAsset(
          projectId: project.project.id,
          fileName: key.substring(prefix.length),
          bytes: content,
        ),
      );
    }
  }
  return (embedded: embedded, omitted: omitted);
}
