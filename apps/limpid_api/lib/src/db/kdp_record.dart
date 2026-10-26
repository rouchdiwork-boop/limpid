/// La gravité d'un problème relevé par le contrôle de soumission.
enum KdpIssueSeverity {
  /// Le problème empêche la soumission : Amazon refuse le dossier.
  blocking('blocking'),

  /// Le problème n'empêche pas la soumission, mais l'auteur doit le
  /// connaître.
  warning('warning');

  const KdpIssueSeverity(this.key);

  /// Le nom technique de la gravité.
  final String key;
}

/// Un problème relevé par le contrôle de soumission.
///
/// Chaque problème nomme le champ fautif et ce qu'il faut corriger : la
/// liste remplace le booléen qu'un contrôle aurait rendu.
final class KdpIssue {
  /// Crée un problème.
  const KdpIssue({
    required this.code,
    required this.field,
    required this.message,
    this.severity = KdpIssueSeverity.blocking,
  });

  /// Le code technique du problème.
  final String code;

  /// Le champ fautif.
  final String field;

  /// Ce qu'il faut corriger, en français.
  final String message;

  /// La gravité du problème.
  final KdpIssueSeverity severity;

  /// Vrai quand le problème empêche la soumission.
  bool get isBlocking => severity == KdpIssueSeverity.blocking;

  /// La représentation JSON du problème.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code,
      'field': field,
      'message': message,
      'severity': severity.key,
    };
  }
}

/// L'état d'une publication préparée.
enum KdpPublicationStatus {
  /// Le dossier passe le contrôle de soumission.
  ready('ready'),

  /// Le dossier porte au moins un problème bloquant.
  blocked('blocked');

  const KdpPublicationStatus(this.key);

  /// Le nom technique de l'état.
  final String key;
}

/// Une publication préparée pour Amazon KDP.
///
/// La trace porte ce qui a été préparé : le livre, la version du
/// manuscrit, les métadonnées, l'horodatage et le résultat du contrôle.
/// L'auteur la relit plus tard pour reprendre sa soumission.
final class KdpPublication {
  /// Crée une publication.
  const KdpPublication({
    required this.id,
    required this.projectId,
    required this.userId,
    required this.title,
    required this.author,
    required this.description,
    required this.keywords,
    required this.categories,
    required this.issues,
    required this.isbn,
    required this.language,
    required this.publisher,
    required this.status,
    required this.wordCount,
    required this.pageCount,
    required this.epubKey,
    required this.pdfKey,
    required this.epubBytes,
    required this.pdfBytes,
    required this.manuscriptVersion,
    required this.createdAt,
  });

  /// L'identifiant de la publication.
  final String id;

  /// Le projet publié.
  final String projectId;

  /// Le compte qui a préparé la publication.
  final String userId;

  /// Le titre de l'ouvrage.
  final String title;

  /// Le nom de l'auteur.
  final String author;

  /// Le résumé de l'ouvrage.
  final String description;

  /// Les mots-clés de la fiche produit.
  final List<String> keywords;

  /// Les catégories de la fiche produit.
  final List<String> categories;

  /// Les problèmes relevés par le contrôle de soumission.
  final List<KdpIssue> issues;

  /// L'ISBN de l'édition imprimée.
  final String? isbn;

  /// La langue de l'ouvrage.
  final String language;

  /// L'éditeur de l'ouvrage.
  final String? publisher;

  /// L'état du dossier.
  final KdpPublicationStatus status;

  /// Le nombre de mots du livre.
  final int wordCount;

  /// Le nombre de pages du PDF d'impression.
  final int pageCount;

  /// La clé de l'EPUB dans le stockage.
  final String epubKey;

  /// La clé du PDF d'impression dans le stockage.
  final String pdfKey;

  /// La taille de l'EPUB, en octets.
  final int epubBytes;

  /// La taille du PDF d'impression, en octets.
  final int pdfBytes;

  /// La version du manuscrit au moment de la préparation.
  final String manuscriptVersion;

  /// L'horodatage de la préparation.
  final DateTime createdAt;

  /// Vrai quand le dossier passe le contrôle de soumission.
  bool get isReady => status == KdpPublicationStatus.ready;

  /// La représentation JSON de la publication.
  ///
  /// Les liens de téléchargement sont ajoutés par le service : ils
  /// expirent, la trace ne les porte pas.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'project_id': projectId,
      'user_id': userId,
      'title': title,
      'author': author,
      'description': description,
      'keywords': List<String>.unmodifiable(keywords),
      'categories': List<String>.unmodifiable(categories),
      'isbn': isbn,
      'language': language,
      'publisher': publisher,
      'status': status.key,
      'word_count': wordCount,
      'page_count': pageCount,
      'manuscript_version': manuscriptVersion,
      'created_at': createdAt.toUtc().toIso8601String(),
      'issues': <Object?>[for (final KdpIssue issue in issues) issue.toJson()],
      'artefacts': <String, Object?>{
        'epub': <String, Object?>{'key': epubKey, 'size_in_bytes': epubBytes},
        'pdf': <String, Object?>{'key': pdfKey, 'size_in_bytes': pdfBytes},
      },
    };
  }
}
