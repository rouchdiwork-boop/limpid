import 'package:limpid_app/src/domain/kdp_repository.dart';

/// L'ISBN valide du livre de l'auteur.
const String fakeIsbn = '9782364123458';

/// Construit un dépôt pour le test.
KdpSubmission submissionOf({
  String id = 'pub_1',
  String projectId = 'project_1',
  String title = 'Les Heures de Cendre',
  String author = 'Camille Martin',
  String description = 'Une archiviste et une cloche.',
  List<String> keywords = const <String>['archives', 'mystère'],
  List<String> categories = const <String>['Roman historique'],
  String language = 'fr',
  String publisher = 'Atelier Sandre',
  String? isbn = fakeIsbn,
  KdpState state = KdpState.draft,
  bool isReady = true,
  List<KdpIssue> issues = const <KdpIssue>[],
  KdpRefusal? refusal,
  int wordCount = 48210,
  int pageCount = 212,
  DateTime? createdAt,
  String? depositId,
  String? amazonSubmissionId,
  int attempts = 0,
  DateTime? updatedAt,
}) {
  return KdpSubmission(
    id: id,
    projectId: projectId,
    title: title,
    author: author,
    description: description,
    keywords: keywords,
    categories: categories,
    language: language,
    publisher: publisher,
    isbn: isbn,
    state: state,
    isReady: isReady,
    issues: issues,
    refusal: refusal,
    wordCount: wordCount,
    pageCount: pageCount,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    depositId: depositId,
    amazonSubmissionId: amazonSubmissionId,
    attempts: attempts,
    updatedAt: updatedAt,
  );
}

/// Un dépôt préparé, prêt à partir chez Amazon.
final KdpSubmission fakeSubmission = submissionOf();

/// Un dépôt refusé par Amazon, avec le motif du refus.
final KdpSubmission fakeRefusedSubmission = submissionOf(
  id: 'pub_2',
  state: KdpState.refused,
  depositId: 'dep_2',
  attempts: 1,
  updatedAt: DateTime.utc(2026, 10, 22),
  refusal: const KdpRefusal(
    issues: <KdpIssue>[
      KdpIssue(
        code: 'isbn_already_in_use',
        field: 'isbn',
        message: "L'ISBN indiqué est déjà utilisé par un autre ouvrage.",
      ),
    ],
  ),
);

/// Un dépôt dont le contrôle de soumission a relevé des problèmes.
final KdpSubmission fakeBlockedSubmission = submissionOf(
  id: 'pub_3',
  isReady: false,
  issues: const <KdpIssue>[
    KdpIssue(
      code: 'isbn_missing',
      field: 'isbn',
      message:
          "L'édition imprimée exige un ISBN : ajoutez-le avant de déposer "
          'le dossier sur Amazon.',
    ),
  ],
);

/// Les métadonnées valides du livre de l'auteur.
const KdpMetadata fakeMetadata = KdpMetadata(
  title: 'Les Heures de Cendre',
  author: 'Camille Martin',
  description: 'Une archiviste et une cloche.',
  keywords: <String>['archives', 'mystère'],
  categories: <String>['Roman historique'],
  language: 'fr',
  isbn: fakeIsbn,
);

/// Un [KdpRepository] que le test pilote à la main.
///
/// Le faux tient tout en mémoire : il ne lit rien du serveur et n'écrit
/// rien. Les tests le remplissent, le remplissent d'erreurs et regardent ce
/// qu'il a reçu.
final class FakeKdpRepository implements KdpRepository {
  /// Crée un dépôt servant [submissions].
  FakeKdpRepository({List<KdpSubmission>? submissions})
    : submissions = List<KdpSubmission>.of(
        submissions ?? <KdpSubmission>[fakeSubmission],
      );

  /// Les dépôts que le dépôt sert.
  List<KdpSubmission> submissions;

  /// L'erreur que les lectures lèvent, quand elle est posée.
  Object? error;

  /// L'erreur que la préparation lève, quand elle est posée.
  Object? prepareError;

  /// L'erreur que le dépôt lève, quand elle est posée.
  Object? depositError;

  /// Les métadonnées que la préparation a reçues.
  final List<KdpMetadata> prepared = <KdpMetadata>[];

  /// Les livres que la préparation a reçus.
  final List<String> preparedProjects = <String>[];

  /// Les identifiants des dossiers déposés.
  final List<String> deposited = <String>[];

  /// L'état que le dépôt renvoie.
  KdpState depositState = KdpState.submitted;

  @override
  Future<List<KdpSubmission>> list() async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return List<KdpSubmission>.unmodifiable(submissions);
  }

  @override
  Future<KdpSubmission?> find(String submissionId) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    for (final KdpSubmission submission in submissions) {
      if (submission.id == submissionId) return submission;
    }
    return null;
  }

  @override
  Future<KdpSubmission> prepare({
    required String projectId,
    required KdpMetadata metadata,
  }) async {
    final Object? failure = prepareError;
    if (failure != null) throw failure;
    prepared.add(metadata);
    preparedProjects.add(projectId);
    final KdpSubmission submission = submissionOf(
      id: 'pub_${prepared.length}',
      projectId: projectId,
      title: metadata.composedTitle,
      author: metadata.author,
      description: metadata.description,
      keywords: metadata.keywords,
      categories: metadata.categories,
      language: metadata.language,
      publisher: metadata.publisher,
      isbn: metadata.normalizedIsbn,
    );
    submissions = <KdpSubmission>[submission, ...submissions];
    return submission;
  }

  @override
  Future<KdpSubmission> deposit({required String submissionId}) async {
    final Object? failure = depositError;
    if (failure != null) throw failure;
    deposited.add(submissionId);
    for (final KdpSubmission submission in submissions) {
      if (submission.id != submissionId) continue;
      final KdpSubmission deposited = submission.copyWith(
        state: depositState,
        depositId: 'dep_$submissionId',
        attempts: submission.attempts + 1,
        updatedAt: DateTime.utc(2026, 10, 25),
      );
      submissions = <KdpSubmission>[
        for (final KdpSubmission entry in submissions)
          if (entry.id == submissionId) deposited else entry,
      ];
      return deposited;
    }
    return submissionOf(id: submissionId, state: depositState);
  }
}
