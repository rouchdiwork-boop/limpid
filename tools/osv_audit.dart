// Audit des vulnérabilités connues des dépendances Dart du monorepo.
//
// Le script lit les fichiers `pubspec.lock` résolus, interroge l'API OSV
// (https://osv.dev) par lots et signale toute dépendance connue pour une
// vulnérabilité. Il n'utilise que la bibliothèque standard : `dart:io` et
// `dart:convert` suffisent, l'audit tourne donc sans résolution de
// dépendances et sans paquet tiers.
//
// Usage :
//   dart tools/osv_audit.dart                # audit du monorepo entier
//   dart tools/osv_audit.dart chemin/lock    # audit d'un fichier précis
//
// Codes de sortie :
//   0 — aucune vulnérabilité connue
//   1 — au moins une vulnérabilité connue
//   2 — erreur technique (API injoignable, fichier illisible)

import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Répertoires du monorepo où sont cherchés les fichiers de verrouillage.
const List<String> _lockfileRoots = <String>['apps', 'packages'];

/// Nom de l'écosystème des paquets Dart dans le registre OSV.
const String _pubEcosystem = 'Pub';

/// Adresse de l'API OSV par lot.
const String _osvBatchEndpoint = 'https://api.osv.dev/v1/querybatch';

/// Nombre maximal de dépendances envoyées dans un même lot.
const int _batchSize = 200;

/// Délai d'attente maximal d'une requête.
const Duration _requestTimeout = Duration(seconds: 30);

/// Nombre de tentatives avant d'abandonner une requête.
const int _maxAttempts = 3;

/// Pause entre deux tentatives.
const Duration _retryDelay = Duration(seconds: 5);

/// Longueur maximale de l'extrait d'erreur renvoyé par l'API.
const int _errorExcerptLength = 200;

/// Erreur de l'API OSV : la réponse est illisible ou inattendue.
final class OsvException implements Exception {
  /// Crée une erreur portant le message de l'API.
  const OsvException(this.message);

  /// Message affiché à l'utilisateur.
  final String message;

  @override
  String toString() => 'OsvException: $message';
}

/// Une dépendance résolue, telle que déclarée dans un `pubspec.lock`.
final class ResolvedPackage {
  /// Crée la description d'une dépendance résolue.
  const ResolvedPackage({required this.name, required this.version});

  /// Nom du paquet sur pub.dev.
  final String name;

  /// Version résolue du paquet.
  final String version;

  /// Clé d'identification unique du couple nom/version.
  String get key => '$name@$version';

  @override
  String toString() => key;
}

/// Une vulnérabilité annoncée par l'API OSV pour une dépendance.
final class Advisory {
  /// Crée la description d'une vulnérabilité.
  const Advisory({
    required this.packageName,
    required this.id,
    required this.aliases,
    required this.summary,
    this.fixedVersion,
  });

  /// Nom du paquet concerné.
  final String packageName;

  /// Identifiant de l'avis dans le registre OSV.
  final String id;

  /// Identifiants alternatifs (CVE, GHSA…).
  final List<String> aliases;

  /// Résumé de l'avis.
  final String summary;

  /// Première version corrigée annoncée, quand l'avis en donne une.
  final String? fixedVersion;

  /// Tous les identifiants de l'avis, séparés par des virgules.
  String get references => <String>[id, ...aliases].join(', ');
}

/// En-tête de section d'un `pubspec.lock` : `packages:`, `sdks:`…
final RegExp _sectionPattern = RegExp(r'^([A-Za-z_][A-Za-z0-9_-]*):\s*$');

/// Nom d'un paquet : deux espaces d'indentation, puis le nom et deux-points.
final RegExp _packagePattern = RegExp(r'^ {2}(\S+):\s*$');

/// Version résolue d'un paquet.
final RegExp _versionPattern = RegExp(r'^ {4}version: "?([^"\s]+)"?\s*$');

/// Provenance d'un paquet : `hosted`, `git`, `path`…
final RegExp _sourcePattern = RegExp(r'^ {4}source: (\S+)\s*$');

/// Extrait les dépendances résolues d'un fichier `pubspec.lock`.
///
/// Seuls les paquets publiés sur pub.dev sont retenus : une dépendance tirée
/// d'un dépôt git ou d'un chemin local n'existe pas dans le registre OSV.
List<ResolvedPackage> readLockfile(String content) {
  final _LockfileParser parser = _LockfileParser();
  for (final String line in const LineSplitter().convert(content)) {
    parser.consume(line);
  }
  parser.flush();
  return List<ResolvedPackage>.unmodifiable(parser.packages);
}

/// Lecteur des fichiers `pubspec.lock`.
///
/// Le format est régulier : un paquet tient sur cinq lignes indentées, la
/// version en quatrième position. Le lecteur ne s'appuie que sur cette
/// régularité et ignore tout ce qu'il ne reconnaît pas.
final class _LockfileParser {
  final List<ResolvedPackage> _packages = <ResolvedPackage>[];

  String? _name;
  String? _version;
  String? _source;
  bool _insidePackages = false;

  /// Dépendances reconnues jusqu'ici.
  List<ResolvedPackage> get packages => _packages;

  /// Prend une ligne du fichier en compte.
  void consume(String line) {
    if (line.isEmpty || line.startsWith('#')) {
      return;
    }
    if (_sectionPattern.hasMatch(line)) {
      flush();
      _insidePackages = line.trim() == 'packages:';
      return;
    }
    if (!_insidePackages) {
      return;
    }
    final RegExpMatch? package = _packagePattern.firstMatch(line);
    if (package != null) {
      flush();
      _name = package.group(1);
      return;
    }
    final RegExpMatch? version = _versionPattern.firstMatch(line);
    if (version != null) {
      _version = version.group(1);
      return;
    }
    final RegExpMatch? source = _sourcePattern.firstMatch(line);
    if (source != null) {
      _source = source.group(1);
    }
  }

  /// Ferme le paquet en cours et le mémorise s'il est exploitable.
  void flush() {
    final String? name = _name;
    final String? version = _version;
    if (name != null &&
        version != null &&
        (_source == null || _source == 'hosted')) {
      _packages.add(ResolvedPackage(name: name, version: version));
    }
    _name = null;
    _version = null;
    _source = null;
  }
}

/// Client de l'API OSV.
final class OsvClient {
  /// Crée un client interrogeant l'API OSV.
  const OsvClient({this.endpoint = _osvBatchEndpoint});

  /// Adresse interrogée.
  final String endpoint;

  /// Demande les avis connus pour un lot de dépendances.
  Future<List<Advisory>> advisories(List<ResolvedPackage> batch) async {
    final String payload = jsonEncode(<String, Object?>{
      'queries': batch
          .map(
            (ResolvedPackage package) => <String, Object?>{
              'package': <String, String>{
                'name': package.name,
                'ecosystem': _pubEcosystem,
              },
              'version': package.version,
            },
          )
          .toList(),
    });
    return _readAdvisories(await _post(payload), batch);
  }

  List<Advisory> _readAdvisories(String body, List<ResolvedPackage> batch) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const OsvException('La réponse de l’API OSV n’est pas un objet.');
    }
    final Object? rawResults = decoded['results'];
    if (rawResults is! List<dynamic>) {
      throw const OsvException(
        'La réponse de l’API OSV ne porte pas de résultats.',
      );
    }
    final List<Advisory> advisories = <Advisory>[];
    for (int index = 0; index < rawResults.length; index++) {
      final Object? entry = rawResults[index];
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final Object? rawVulns = entry['vulns'];
      if (rawVulns is! List<dynamic>) {
        continue;
      }
      final String packageName = index < batch.length
          ? batch[index].name
          : 'inconnue';
      for (final Object? vuln in rawVulns) {
        if (vuln is! Map<String, dynamic>) {
          continue;
        }
        advisories.add(_readAdvisory(vuln, packageName));
      }
    }
    return advisories;
  }

  Advisory _readAdvisory(Map<String, dynamic> json, String packageName) {
    final Object? rawAliases = json['aliases'];
    final Object? rawId = json['id'];
    final Object? rawSummary = json['summary'];
    return Advisory(
      packageName: packageName,
      id: rawId is String ? rawId : 'identifiant inconnu',
      aliases: List<String>.unmodifiable(
        rawAliases is List<dynamic>
            ? <String>[
                for (final Object? alias in rawAliases)
                  if (alias is String) alias,
              ]
            : const <String>[],
      ),
      summary: rawSummary is String ? rawSummary : 'Aucune description.',
      fixedVersion: _readFixedVersion(json),
    );
  }

  String? _readFixedVersion(Map<String, dynamic> json) {
    final Object? affected = json['affected'];
    if (affected is! List<dynamic>) {
      return null;
    }
    for (final Object? entry in affected) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final Object? ranges = entry['ranges'];
      if (ranges is! List<dynamic>) {
        continue;
      }
      for (final Object? range in ranges) {
        if (range is! Map<String, dynamic>) {
          continue;
        }
        final Object? events = range['events'];
        if (events is! List<dynamic>) {
          continue;
        }
        for (final Object? event in events) {
          if (event is! Map<String, dynamic>) {
            continue;
          }
          final Object? fixed = event['fixed'];
          if (fixed is String && fixed.isNotEmpty) {
            return fixed;
          }
        }
      }
    }
    return null;
  }

  Future<String> _post(String payload) async {
    Object? lastError;
    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        return await _postOnce(payload);
      } on OsvException {
        rethrow;
      } on Exception catch (error) {
        lastError = error;
      }
      if (attempt < _maxAttempts) {
        await Future<void>.delayed(_retryDelay);
      }
    }
    throw OsvException('L’API OSV est injoignable : $lastError');
  }

  Future<String> _postOnce(String payload) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(_requestTimeout);
      request.headers.contentType = ContentType.json;
      request.write(payload);
      final HttpClientResponse response = await request.close().timeout(
        _requestTimeout,
      );
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw OsvException(
          'L’API OSV a répondu ${response.statusCode} : ${_excerpt(body)}',
        );
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  String _excerpt(String body) {
    final String trimmed = body.trim();
    return trimmed.length <= _errorExcerptLength
        ? trimmed
        : '${trimmed.substring(0, _errorExcerptLength)}…';
  }
}

/// Trouve les fichiers de verrouillage du monorepo.
///
/// Le verrouillage de la racine est pris en compte : il porte les
/// dépendances de l'outillage (Melos, les règles de lint).
List<File> findLockfiles({List<String> roots = _lockfileRoots}) {
  final List<File> found = <File>[];
  final File rootLockfile = File('pubspec.lock');
  if (rootLockfile.existsSync()) {
    found.add(rootLockfile);
  }
  for (final String root in roots) {
    final Directory directory = Directory(root);
    if (!directory.existsSync()) {
      continue;
    }
    for (final FileSystemEntity entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('pubspec.lock')) {
        found.add(entity);
      }
    }
  }
  found.sort((File a, File b) => a.path.compareTo(b.path));
  return List<File>.unmodifiable(found);
}

/// Conduit l'audit et rend compte sur la sortie standard.
Future<int> audit(List<String> arguments) async {
  final List<File> lockfiles = arguments.isEmpty
      ? findLockfiles()
      : arguments.map((String path) => File(path)).toList();
  if (lockfiles.isEmpty) {
    stdout.writeln('Aucun fichier pubspec.lock : audit sans objet.');
    return 0;
  }

  final Map<String, ResolvedPackage> packages = <String, ResolvedPackage>{};
  for (final File file in lockfiles) {
    for (final ResolvedPackage package in readLockfile(
      file.readAsStringSync(),
    )) {
      packages[package.key] = package;
    }
  }

  final List<ResolvedPackage> resolved = packages.values.toList();
  stdout.writeln(
    'Audit OSV — ${resolved.length} dépendances résolues, '
    '${lockfiles.length} fichiers de verrouillage.',
  );

  const OsvClient client = OsvClient();
  final List<Advisory> advisories = <Advisory>[];
  for (int start = 0; start < resolved.length; start += _batchSize) {
    final int end = min(start + _batchSize, resolved.length);
    advisories.addAll(await client.advisories(resolved.sublist(start, end)));
  }

  advisories.sort((Advisory a, Advisory b) {
    final int byPackage = a.packageName.compareTo(b.packageName);
    return byPackage != 0 ? byPackage : a.id.compareTo(b.id);
  });

  if (advisories.isEmpty) {
    stdout.writeln(
      'Aucune vulnérabilité connue dans les dépendances résolues.',
    );
    return 0;
  }
  for (final Advisory advisory in advisories) {
    stdout.writeln('• ${advisory.packageName} — ${advisory.references}');
    stdout.writeln('  ${advisory.summary}');
    final String? fixed = advisory.fixedVersion;
    if (fixed != null) {
      stdout.writeln('  Version corrigée : $fixed');
    }
  }
  stdout.writeln('${advisories.length} vulnérabilité(s) connue(s).');
  return 1;
}

/// Point d'entrée : audite le monorepo et rend le code de sortie.
Future<void> main(List<String> arguments) async {
  try {
    exitCode = await audit(arguments);
  } on OsvException catch (error) {
    stderr.writeln('Audit impossible : ${error.message}');
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln('Fichier de verrouillage illisible : ${error.path}');
    exitCode = 2;
  } on Exception catch (error) {
    stderr.writeln('Audit impossible : $error');
    exitCode = 2;
  }
}
