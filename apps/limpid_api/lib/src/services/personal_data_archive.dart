import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../db/audit_entry.dart';
import '../db/project_record.dart';
import '../db/quota_database.dart';
import '../db/sync_op_record.dart';
import '../sync/tree_builder.dart';
import 'personal_data_export.dart';

/// Le nom du manifeste, à la racine de l'archive.
///
/// Le manifeste décrit le contenu de l'archive : ce qu'elle porte, le
/// format de chaque fichier, la date de l'export et sa version.
const String personalDataManifestName = 'manifest.json';

/// Le format de l'archive : un conteneur ZIP.
const String personalDataArchiveFormat = 'zip';

/// Le type de l'archive, annoncé à l'auteur.
const String personalDataArchiveMimeType = 'application/zip';

/// Le nombre maximal d'artefacts embarqués dans l'archive.
///
/// L'export est fabriqué en mémoire : un compte portant un nombre
/// d'artefacts déraisonnable ne doit pas faire tomber le serveur. L'archive
/// dit combien d'artefacts elle a laissés de côté.
const int personalDataMaxAssets = 200;

/// Le nombre maximal d'octets d'artefacts embarqués dans l'archive.
const int personalDataMaxAssetBytes = 64 * 1024 * 1024;

/// Un artefact du compte, lu dans le stockage objet.
final class PersonalDataAsset {
  /// Crée un artefact.
  const PersonalDataAsset({
    required this.projectId,
    required this.fileName,
    required this.bytes,
  });

  /// Le livre auquel l'artefact appartient.
  final String projectId;

  /// Le nom du fichier, tel que le stockage le porte.
  final String fileName;

  /// Le contenu de l'artefact.
  final Uint8List bytes;
}

/// Une entrée de l'archive.
final class ArchiveEntry {
  /// Crée une entrée.
  const ArchiveEntry({
    required this.path,
    required this.format,
    required this.bytes,
  });

  /// Le chemin de l'entrée dans l'archive.
  final String path;

  /// Le format du contenu : `json`, `md`, `epub`…
  final String format;

  /// Le contenu de l'entrée.
  final Uint8List bytes;
}

/// L'archive des données personnelles d'un compte.
final class PersonalDataArchive {
  /// Crée une archive.
  const PersonalDataArchive({
    required this.fileName,
    required this.bytes,
    required this.entries,
    required this.counts,
  });

  /// Le nom du fichier proposé à l'auteur.
  final String fileName;

  /// Le contenu du ZIP.
  final Uint8List bytes;

  /// Les entrées de l'archive, dans l'ordre où elles sont écrites.
  final List<ArchiveEntry> entries;

  /// Le compte de chaque catégorie de l'archive.
  final Map<String, Object?> counts;
}

/// La fabrication de l'archive des données personnelles d'un compte.
///
/// L'archive est organisée par catégorie, et par livre à l'intérieur de la
/// catégorie des manuscrits :
///
/// ```text
/// manifest.json
/// account/account.json               l'identité du compte
/// account/plan.json                  la formule et sa période
/// account/usage.json                 la consommation, période par période
/// account/settings.json              les réglages, sans les secrets
/// account/audit-log.json             l'historique entier du compte
/// projects/<id>/project.json         la ligne du livre
/// projects/<id>/chapters.json        les chapitres du livre
/// projects/<id>/operations.json      les opérations du journal
/// projects/<id>/documents/<id>.json  le manuscrit, comme arbre
/// projects/<id>/manuscript/<id>.md   le manuscrit, lisible
/// assets/<id>/<fichier>              les artefacts du livre
/// ```
///
/// **Aucun secret ne voyage dans l'archive.** Le secret de la double
/// authentification, le secret d'un point de rappel et l'empreinte d'une
/// clé d'API sont des secrets, et non des données personnelles : ils
/// restent dans leur magasin.
abstract final class PersonalDataArchiveBuilder {
  /// Fabrique l'archive de [export], avec les [assets] du compte.
  ///
  /// Les entrées sont écrites dans un ordre stable : deux exports du même
  /// compte portent les mêmes fichiers, dans le même ordre.
  ///
  /// [omittedAssets] est le nombre d'artefacts que l'export n'a pas pu
  /// embarquer : l'archive le dit, plutôt que de laisser croire que le
  /// compte n'avait rien d'autre.
  static PersonalDataArchive build({
    required PersonalDataExport export,
    List<PersonalDataAsset> assets = const <PersonalDataAsset>[],
    int omittedAssets = 0,
  }) {
    final List<ArchiveEntry> entries = <ArchiveEntry>[
      ..._accountEntries(export),
      ..._projectEntries(export),
      ..._assetEntries(assets),
    ];
    final List<ArchiveEntry> all = <ArchiveEntry>[
      _manifest(export, entries, omittedAssets),
      ...entries,
    ];
    return PersonalDataArchive(
      fileName: _fileName(export.exportedAt),
      bytes: _ZipWriter().build(all),
      entries: all,
      counts: _counts(export, entries, omittedAssets),
    );
  }

  /// Les entrées du compte : son identité, ses réglages, son historique.
  static List<ArchiveEntry> _accountEntries(PersonalDataExport export) {
    return <ArchiveEntry>[
      _json('account/account.json', <String, Object?>{
        'user_id': export.userId,
        'email': export.email,
        'exported_at': export.exportedAt.toUtc().toIso8601String(),
        'format_version': personalDataExportFormatVersion,
      }),
      _json('account/plan.json', <String, Object?>{
        'is_free': export.plan == null,
        'plan': export.plan?.toJson(),
      }),
      _json('account/usage.json', <String, Object?>{
        'usages': <Map<String, Object?>>[
          for (final QuotaUsage usage in export.usages)
            <String, Object?>{
              'feature': usage.feature.key,
              'period': usage.periodKey,
              'quantity': usage.quantity,
            },
        ],
      }),
      _json('account/settings.json', <String, Object?>{
        'two_factor': export.settings.twoFactor,
        'api_keys': export.settings.apiKeys,
        'webhook_endpoints': export.settings.endpoints,
        'teams': export.settings.teams,
      }),
      _json('account/audit-log.json', <String, Object?>{
        'count': export.auditEntries.length,
        'truncated': export.auditTruncated,
        'entries': <Map<String, Object?>>[
          for (final AuditEntry entry in export.auditEntries) entry.toJson(),
        ],
      }),
    ];
  }

  /// Les entrées des livres : le manuscrit et le journal.
  static List<ArchiveEntry> _projectEntries(PersonalDataExport export) {
    final List<ArchiveEntry> entries = <ArchiveEntry>[];
    for (final PersonalDataProject project in export.projects) {
      final String base = 'projects/${_segment(project.project.id)}';
      entries.add(
        _json('$base/project.json', <String, Object?>{
          'project': _projectJson(project.project),
          'scope': project.scope,
        }),
      );
      entries.add(
        _json('$base/chapters.json', <String, Object?>{
          'chapters': _chapters(project.documents),
        }),
      );
      entries.add(
        _json('$base/operations.json', <String, Object?>{
          'operations': <Map<String, Object?>>[
            for (final SyncOpRecord operation in project.operations)
              operation.toJson(),
          ],
        }),
      );
      for (final DocumentTree document in project.documents) {
        final String name = _segment(document.docId);
        entries.add(_json('$base/documents/$name.json', document.toJson()));
        entries.add(
          ArchiveEntry(
            path: '$base/manuscript/$name.md',
            format: 'md',
            bytes: _utf8(_manuscript(document)),
          ),
        );
      }
    }
    return entries;
  }

  /// Les entrées des artefacts du compte.
  static List<ArchiveEntry> _assetEntries(List<PersonalDataAsset> assets) {
    return <ArchiveEntry>[
      for (final PersonalDataAsset asset in assets)
        ArchiveEntry(
          path:
              'assets/${_segment(asset.projectId)}/'
              '${_segment(asset.fileName)}',
          format: _formatOf(asset.fileName),
          bytes: asset.bytes,
        ),
    ];
  }

  /// Le manifeste, décrivant le contenu de l'archive.
  static ArchiveEntry _manifest(
    PersonalDataExport export,
    List<ArchiveEntry> entries,
    int omittedAssets,
  ) {
    return _json(personalDataManifestName, <String, Object?>{
      'format': 'limpid-account-export',
      'format_version': personalDataExportFormatVersion,
      'exported_at': export.exportedAt.toUtc().toIso8601String(),
      'account': <String, Object?>{
        'user_id': export.userId,
        'email': export.email,
      },
      'contents': <Map<String, Object?>>[
        <String, Object?>{'path': personalDataManifestName, 'format': 'json'},
        for (final ArchiveEntry entry in entries)
          <String, Object?>{
            'path': entry.path,
            'format': entry.format,
            'bytes': entry.bytes.length,
          },
      ],
      'counts': _counts(export, entries, omittedAssets),
      'notes': <String>[
        'Cette archive porte vos données personnelles : vos livres, vos '
            'réglages et l\'historique de votre compte.',
        'Les secrets du compte — le secret de la double authentification, '
            'le secret d\'un point de rappel, l\'empreinte d\'une clé '
            'd\'API — ne figurent pas dans l\'archive : ce sont des '
            'secrets, pas des données personnelles.',
        'Sur un livre que vous ne possédez que comme co-auteur, l\'archive '
            'ne porte que vos propres opérations.',
        if (omittedAssets > 0)
          '$omittedAssets artefact(s) du compte n\'ont pas pu être '
              'embarqués : la limite de l\'export a été atteinte. Le '
              'nombre exact figure dans « counts.assets_omitted ».',
        if (export.auditTruncated)
          'L\'historique du compte est plus long que la borne de l\'export : '
              'l\'archive porte les $personalDataAuditLimit entrées les '
              'plus récentes. Le journal complet est conservé par le '
              'service.',
      ],
    });
  }

  /// Le compte de chaque catégorie de l'archive.
  static Map<String, Object?> _counts(
    PersonalDataExport export,
    List<ArchiveEntry> entries,
    int omittedAssets,
  ) {
    return <String, Object?>{
      'projects': export.projects.length,
      'documents': export.documentCount,
      'sync_operations': export.operationCount,
      'audit_entries': export.auditEntries.length,
      'audit_truncated': export.auditTruncated,
      'assets': entries
          .where((ArchiveEntry entry) => entry.path.startsWith('assets/'))
          .length,
      'assets_omitted': omittedAssets,
      'files': entries.length + 1,
    };
  }

  /// La ligne du livre, la suppression douce comprise.
  ///
  /// L'archive porte aussi les livres supprimés : leurs lignes vivent
  /// trente jours (D-19) et appartiennent à l'auteur jusqu'à la purge.
  static Map<String, Object?> _projectJson(ProjectRecord project) {
    return <String, Object?>{
      'id': project.id,
      'owner_id': project.ownerId,
      'title': project.title,
      'synopsis': project.synopsis,
      'status': project.status.name,
      'language': project.language,
      'order_key': project.orderKey,
      'is_public': project.isPublic,
      'created_at': project.createdAt.toUtc().toIso8601String(),
      'updated_at': project.updatedAt.toUtc().toIso8601String(),
      'deleted_at': project.deletedAt?.toUtc().toIso8601String(),
    };
  }

  /// Les chapitres d'un livre, un par document.
  ///
  /// Le manuscrit est stocké comme un journal d'opérations : un document
  /// est une scène, et le livre exporté associe un document à un chapitre
  /// (voir `BookBuilder`). L'archive garde cette association, pour que
  /// l'auteur lise la structure qu'il a écrite.
  static List<Map<String, Object?>> _chapters(List<DocumentTree> documents) {
    final List<Map<String, Object?>> chapters = <Map<String, Object?>>[];
    for (var index = 0; index < documents.length; index++) {
      final DocumentTree document = documents[index];
      final String title = document.meta['title'] ?? 'Chapitre ${index + 1}';
      chapters.add(<String, Object?>{
        'id': document.docId,
        'title': title,
        'order': index,
        'scenes': <Map<String, Object?>>[
          <String, Object?>{
            'id': document.docId,
            'document_id': document.docId,
            'title': title,
          },
        ],
      });
    }
    return chapters;
  }

  /// Le manuscrit d'un document, en Markdown.
  ///
  /// L'archive porte le manuscrit deux fois : comme l'arbre que le journal
  /// reconstruit, qui est toute la vérité, et comme un texte que l'auteur
  /// lit sans aucun outil.
  static String _manuscript(DocumentTree document) {
    final StringBuffer buffer = StringBuffer();
    final String title = document.meta['title'] ?? document.docId;
    buffer.writeln('# $title');
    buffer.writeln();
    for (final BlockNode block in document.blocks) {
      _writeBlock(buffer, block);
    }
    return buffer.toString();
  }

  /// Écrit un bloc, et les blocs qu'il porte.
  static void _writeBlock(StringBuffer buffer, BlockNode block) {
    final String text = block.content.trim();
    if (text.isNotEmpty) {
      switch (block.type) {
        case 'heading1':
          buffer.writeln('# $text');
          buffer.writeln();
        case 'heading2':
          buffer.writeln('## $text');
          buffer.writeln();
        case 'heading3':
          buffer.writeln('### $text');
          buffer.writeln();
        case 'quote':
          buffer.writeln('> $text');
          buffer.writeln();
        case 'code':
          buffer
            ..writeln('```')
            ..writeln(text)
            ..writeln('```')
            ..writeln();
        case 'listItem':
          buffer.writeln('- $text');
        case 'sceneBreak':
          buffer
            ..writeln('---')
            ..writeln();
        default:
          buffer
            ..writeln(text)
            ..writeln();
      }
    }
    for (final BlockNode child in block.children) {
      _writeBlock(buffer, child);
    }
  }

  /// Fabrique une entrée JSON.
  static ArchiveEntry _json(String path, Map<String, Object?> payload) {
    return ArchiveEntry(
      path: path,
      format: 'json',
      bytes: _utf8(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  /// Le nom du fichier proposé à l'auteur.
  static String _fileName(DateTime moment) {
    final DateTime day = moment.toUtc();
    final String month = day.month.toString().padLeft(2, '0');
    final String date = day.day.toString().padLeft(2, '0');
    return 'limpid-donnees-${day.year}-$month-$date.zip';
  }

  /// Le format d'un fichier, lu dans son extension.
  static String _formatOf(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return 'binary';
    return fileName.substring(dot + 1).toLowerCase();
  }

  /// Un segment de chemin sûr pour une archive.
  ///
  /// Les identifiants viennent des clients : un segment ne doit jamais
  /// porter de séparateur, ni remonter l'arborescence de l'archive. Un
  /// segment fait de points — `.` et `..` — perd donc ses points : il
  /// reste un nom de fichier, jamais un chemin.
  static String _segment(String value) {
    final String cleaned = value
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'^\.+'), '_');
    if (cleaned.isEmpty) return 'sans-nom';
    return cleaned.length <= 64 ? cleaned : cleaned.substring(0, 64);
  }

  /// Les octets d'un texte.
  static Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));
}

/// L'écriture d'un conteneur ZIP.
///
/// Le conteneur est écrit ici, sans dépendance : `dart:io` compresse en
/// DEFLATE mais n'écrit pas les enveloppes du format. Les entrées sont
/// estampées d'une date fixe, pour que deux archives portant le même
/// contenu portent les mêmes octets.
final class _ZipWriter {
  static const int _localSignature = 0x04034b50;
  static const int _centralSignature = 0x02014b50;
  static const int _endSignature = 0x06054b50;
  static const int _deflate = 8;
  static const int _utf8Flag = 0x0800;
  static const int _version = 20;

  /// La date estampée sur chaque entrée : le premier janvier 2020.
  static const int _dosTime = 0;
  static const int _dosDate = (20 << 9) | (1 << 5) | 1;

  /// Le CRC-32 des contenus, table bâtie une fois.
  static final List<int> _crcTable = List<int>.generate(256, (int index) {
    int value = index;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) == 1 ? 0xedb88320 ^ (value >> 1) : value >> 1;
    }
    return value;
  });

  /// Écrit l'archive des [entries].
  Uint8List build(List<ArchiveEntry> entries) {
    final BytesBuilder body = BytesBuilder();
    final List<_CentralRecord> directory = <_CentralRecord>[];

    for (final ArchiveEntry entry in entries) {
      final Uint8List name = Uint8List.fromList(utf8.encode(entry.path));
      final Uint8List compressed = Uint8List.fromList(
        ZLibCodec(raw: true).encode(entry.bytes),
      );
      final int checksum = _crc32(entry.bytes);
      final int offset = body.length;
      body.add(
        _localHeader(name, checksum, compressed.length, entry.bytes.length),
      );
      body.add(compressed);
      directory.add(
        _CentralRecord(
          name: name,
          checksum: checksum,
          compressedSize: compressed.length,
          size: entry.bytes.length,
          offset: offset,
        ),
      );
    }

    final Uint8List content = body.toBytes();
    final BytesBuilder central = BytesBuilder();
    for (final _CentralRecord record in directory) {
      central.add(_centralHeader(record));
    }
    final Uint8List centralBytes = central.toBytes();

    return Uint8List.fromList(<int>[
      ...content,
      ...centralBytes,
      ..._endRecord(directory.length, centralBytes.length, content.length),
    ]);
  }

  /// L'en-tête écrit avant le contenu d'une entrée.
  Uint8List _localHeader(
    Uint8List name,
    int checksum,
    int compressedSize,
    int size,
  ) {
    final ByteData data = ByteData(30);
    data.setUint32(0, _localSignature, Endian.little);
    data.setUint16(4, _version, Endian.little);
    data.setUint16(6, _utf8Flag, Endian.little);
    data.setUint16(8, _deflate, Endian.little);
    data.setUint16(10, _dosTime, Endian.little);
    data.setUint16(12, _dosDate, Endian.little);
    data.setUint32(14, checksum, Endian.little);
    data.setUint32(18, compressedSize, Endian.little);
    data.setUint32(22, size, Endian.little);
    data.setUint16(26, name.length, Endian.little);
    data.setUint16(28, 0, Endian.little);
    return Uint8List.fromList(<int>[...data.buffer.asUint8List(), ...name]);
  }

  /// L'en-tête écrit dans le répertoire central, pour une entrée.
  Uint8List _centralHeader(_CentralRecord record) {
    final ByteData data = ByteData(46);
    data.setUint32(0, _centralSignature, Endian.little);
    data.setUint16(4, _version, Endian.little);
    data.setUint16(6, _version, Endian.little);
    data.setUint16(8, _utf8Flag, Endian.little);
    data.setUint16(10, _deflate, Endian.little);
    data.setUint16(12, _dosTime, Endian.little);
    data.setUint16(14, _dosDate, Endian.little);
    data.setUint32(16, record.checksum, Endian.little);
    data.setUint32(20, record.compressedSize, Endian.little);
    data.setUint32(24, record.size, Endian.little);
    data.setUint16(28, record.name.length, Endian.little);
    data.setUint16(30, 0, Endian.little);
    data.setUint16(32, 0, Endian.little);
    data.setUint16(34, 0, Endian.little);
    data.setUint16(36, 0, Endian.little);
    data.setUint32(38, 0, Endian.little);
    data.setUint32(42, record.offset, Endian.little);
    return Uint8List.fromList(<int>[
      ...data.buffer.asUint8List(),
      ...record.name,
    ]);
  }

  /// L'enregistrement qui ferme le répertoire central.
  Uint8List _endRecord(int count, int centralSize, int centralOffset) {
    final ByteData data = ByteData(22);
    data.setUint32(0, _endSignature, Endian.little);
    data.setUint16(4, 0, Endian.little);
    data.setUint16(6, 0, Endian.little);
    data.setUint16(8, count, Endian.little);
    data.setUint16(10, count, Endian.little);
    data.setUint32(12, centralSize, Endian.little);
    data.setUint32(16, centralOffset, Endian.little);
    data.setUint16(20, 0, Endian.little);
    return data.buffer.asUint8List();
  }

  /// Le CRC-32 de [bytes], la somme que le format porte.
  static int _crc32(List<int> bytes) {
    var checksum = 0xffffffff;
    for (final int byte in bytes) {
      checksum =
          _crcTable[(checksum ^ byte) & 0xff] ^ ((checksum >> 8) & 0xffffff);
    }
    return (checksum ^ 0xffffffff) & 0xffffffff;
  }
}

/// L'enregistrement d'une entrée dans le répertoire central.
final class _CentralRecord {
  /// Crée un enregistrement.
  const _CentralRecord({
    required this.name,
    required this.checksum,
    required this.compressedSize,
    required this.size,
    required this.offset,
  });

  /// Le nom de l'entrée, en UTF-8.
  final Uint8List name;

  /// Le CRC-32 du contenu.
  final int checksum;

  /// La taille du contenu compressé.
  final int compressedSize;

  /// La taille du contenu.
  final int size;

  /// La position de l'en-tête local, dans l'archive.
  final int offset;
}
