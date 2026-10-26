import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:limpid_api/limpid_api.dart';
import 'package:limpid_core/limpid_core.dart' hide ExportJobStatus;
import 'package:test/test.dart';

import 'helpers/export_test_server.dart';

/// Le budget de fabrication d'un EPUB, en secondes.
///
/// Le livre de 80 000 mots est le livre de référence de la plateforme.
const Duration epubBudget = Duration(seconds: 8);

/// Le budget de fabrication d'un PDF reflowable, en secondes.
const Duration pdfBudget = Duration(seconds: 20);

/// Le budget de fabrication d'un PDF print-ready, en secondes.
const Duration printBudget = Duration(seconds: 45);

/// Le rapport toléré entre la mesure et le budget.
///
/// Le poste de développement n'est pas la machine de production : une
/// mesure plus lente que le budget est **notée** quand elle reste dans
/// ce rapport. Au-delà, la mesure décrit un défaut, pas une machine
/// lente.
const double budgetTolerance = 4;

/// Le nombre de mots du livre de référence.
const int referenceWordCount = 80000;

/// Le nombre de blocs du livre de référence.
const int referenceBlockCount = 400;

/// Le nombre de mots d'un bloc du livre de référence.
const int referenceWordsPerBlock = referenceWordCount ~/ referenceBlockCount;

/// La mesure d'un export.
///
/// La mesure porte le temps de fabrication : le worker produit l'artefact
/// et le range dans le stockage.
class _Measurement {
  /// Crée une mesure.
  const _Measurement({
    required this.format,
    required this.budget,
    required this.elapsed,
    required this.status,
    required this.bytes,
  });

  /// Le format mesuré.
  final String format;

  /// Le budget du format.
  final Duration budget;

  /// Le temps mesuré.
  final Duration elapsed;

  /// L'état du travail.
  final ExportJobStatus status;

  /// La taille de l'artefact produit.
  final int bytes;

  /// Le rapport entre la mesure et le budget.
  double get ratio => elapsed.inMicroseconds / budget.inMicroseconds;

  /// La mesure tient dans le budget.
  bool get isWithinBudget => elapsed <= budget;
}

void main() {
  group('budget d\'export', () {
    late ExportTestServer server;
    late Map<String, String> auth;
    late String projectId;

    setUp(() async {
      server = await ExportTestServer.start();
      // La formule Pro ouvre les exports imprimes : elle exige la double
      // authentification (D-19), et la preuve accompagne les appels.
      await server.givePlan('user-1', SubscriptionPlan.pro);
      auth = <String, String>{
        'authorization': 'Bearer ${server.tokenFor('user-1')}',
        'x-limpid-2fa': await server.enableTwoFactor('user-1'),
      };
      projectId = await _createProject(server, auth);
      await _pushReferenceBook(server, auth, projectId);
    });

    tearDown(() async {
      await server.stop();
    });

    test(
      'le livre de 80 000 mots est exporte dans les trois formats',
      () async {
        // La mesure ne vaut que si le livre porte bien ses 80 000 mots.
        expect(await _wordsOf(server, projectId), referenceWordCount);

        final _Measurement epub = await _measure(
          server,
          auth,
          projectId,
          'epub',
        );
        final _Measurement pdf = await _measure(server, auth, projectId, 'pdf');
        final _Measurement printReady = await _measure(
          server,
          auth,
          projectId,
          'pdf-print',
        );

        for (final _Measurement measurement in <_Measurement>[
          epub,
          pdf,
          printReady,
        ]) {
          // ignore: avoid_print
          print(
            'export ${measurement.format} : '
            '${measurement.elapsed.inMilliseconds} ms pour '
            '${measurement.bytes} octets '
            '(budget ${measurement.budget.inSeconds} s, '
            'rapport ${measurement.ratio.toStringAsFixed(2)})',
          );
          expect(
            measurement.status,
            ExportJobStatus.succeeded,
            reason: 'L\'export ${measurement.format} doit aboutir.',
          );
          expect(measurement.bytes, greaterThan(0));

          if (measurement.isWithinBudget) {
            expect(
              measurement.ratio,
              lessThanOrEqualTo(1),
              reason: 'L\'export ${measurement.format} tient dans son budget.',
            );
            continue;
          }
          // La machine de développement est plus lente que la machine de
          // production : la mesure est notée, et le rapport doit dire de
          // combien elle s'écarte du budget.
          expect(
            measurement.ratio,
            lessThanOrEqualTo(budgetTolerance),
            reason:
                'L\'export ${measurement.format} dépasse son budget de plus '
                'de ${budgetTolerance.toStringAsFixed(0)} fois : la mesure '
                'décrit un défaut, pas une machine lente.',
          );
        }
      },
    );
  });
}

/// Mesure le temps de fabrication d'un export.
Future<_Measurement> _measure(
  ExportTestServer server,
  Map<String, String> auth,
  String projectId,
  String format,
) async {
  final Stopwatch watch = Stopwatch()..start();
  final http.Response response = await server.post(
    '/v1/export/$format',
    headers: auth,
    body: <String, Object?>{'project_id': projectId},
  );
  expect(response.statusCode, 202);
  final String jobId =
      ((jsonDecode(response.body) as Map<String, dynamic>)['data']
              as Map<String, dynamic>)['id']!
          as String;
  await server.runWorker();
  watch.stop();

  final ExportJobRecord? job = await server.job(jobId);
  expect(job, isNotNull);
  final String? key = server.storage.keys.isEmpty
      ? null
      : server.storage.keys.last;
  final Uint8List? bytes = key == null
      ? null
      : await (server.storage as ObjectStorageReader).readObject(key: key);
  return _Measurement(
    format: format,
    budget: switch (format) {
      'epub' => epubBudget,
      'pdf' => pdfBudget,
      _ => printBudget,
    },
    elapsed: watch.elapsed,
    status: job!.status,
    bytes: bytes?.length ?? 0,
  );
}

/// Un paragraphe de [referenceWordsPerBlock] mots.
///
/// Les mots sont tires au hasard : un texte repetitif se compresse trop
/// bien, et la mesure ne dirait rien du cout reel de la fabrication.
String _paragraphOf(int seed) {
  final math.Random random = math.Random(seed);
  return List<String>.generate(referenceWordsPerBlock, (int _) {
    final int length = 3 + random.nextInt(7);
    return String.fromCharCodes(
      List<int>.generate(length, (int _) => 97 + random.nextInt(26)),
    );
  }).join(' ');
}

/// La cle d'ordre du bloc [index].
///
/// La cle est canonique : elle ne finit jamais par un zero, sauf la cle
/// basse `0`. Une cle qui finit par un zero est refusee par le protocole,
/// et le bloc qu'elle porte disparaitrait du livre.
String _orderKeyOf(int index) {
  final String key = '${index + 1}';
  if (key.length > 1 && key.endsWith('0')) return '${key}1';
  return key;
}

/// Le nombre de mots que porte le livre [projectId].
Future<int> _wordsOf(ExportTestServer server, String projectId) async {
  final List<SyncOpRecord> operations = await server.dependencies.sync.all(
    projectId: projectId,
  );
  var words = 0;
  for (final DocumentTree tree in TreeBuilder.build(operations)) {
    for (final BlockNode block in tree.blocks) {
      words += block.content
          .split(RegExp(r'\s+'))
          .where((String word) => word.isNotEmpty)
          .length;
    }
  }
  return words;
}

/// Crée un projet et rend son identifiant.
Future<String> _createProject(
  ExportTestServer server,
  Map<String, String> headers,
) async {
  final http.Response response = await server.post(
    '/v1/projects',
    headers: headers,
    body: <String, Object?>{'title': 'Le livre de reference'},
  );
  final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;
  return (body['data'] as Map<String, dynamic>)['id'] as String;
}

/// Ecrit le livre de reference : 80 000 mots, en blocs.
///
/// Les operations sont envoyees par lots : la route en accepte deux cents
/// a la fois.
Future<void> _pushReferenceBook(
  ExportTestServer server,
  Map<String, String> headers,
  String projectId,
) async {
  const int operationsPerBatch = 200;

  var written = 0;
  var lamport = 0;
  while (written < referenceBlockCount) {
    final int batch = written + operationsPerBatch > referenceBlockCount
        ? referenceBlockCount - written
        : operationsPerBatch;
    final List<Map<String, Object?>> operations = <Map<String, Object?>>[
      for (int index = 0; index < batch; index++)
        <String, Object?>{
          'op_id': 'op-${written + index}',
          'doc_id': 'doc-1',
          'lamport': ++lamport,
          'author_id': 'user-1',
          'type': 'insertBlock',
          'payload': <String, Object?>{
            'block_id': 'block-${written + index}',
            'parent_id': null,
            'order_key': _orderKeyOf(written + index),
            'type': 'paragraph',
            'content': _paragraphOf(written + index),
          },
          'schema_version': 1,
        },
    ];
    final http.Response response = await server.post(
      '/v1/projects/$projectId/ops',
      headers: headers,
      body: <String, Object?>{'operations': operations},
    );
    expect(response.statusCode, 200, reason: 'Les operations doivent passer.');
    written += batch;
  }
}
