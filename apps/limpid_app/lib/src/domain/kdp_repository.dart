/// La publication d'un livre chez Amazon Kindle Direct Publishing.
///
/// Le contrat vit dans la couche domaine : l'écran de publication le
/// nomme, l'implémentation de la couche données le réalise — aucun des deux
/// ne connaît l'autre. Les types qu'il manipule sont **immuables** : l'écran
/// lit un état, il ne le modifie jamais.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:limpid_app/src/domain/providers.dart';

/// Les champs que la fiche produit d'Amazon porte.
///
/// Les noms sont ceux que le serveur emploie : ils servent à nommer le
/// champ fautif, dans la réponse du serveur comme dans l'écran.
abstract final class KdpFields {
  /// Le titre de l'ouvrage.
  static const String title = 'title';

  /// Le sous-titre de l'ouvrage.
  static const String subtitle = 'subtitle';

  /// Le nom de l'auteur.
  static const String author = 'author';

  /// Le résumé de l'ouvrage.
  static const String description = 'description';

  /// Les mots-clés de la fiche produit.
  static const String keywords = 'keywords';

  /// Les catégories BISAC de la fiche produit.
  static const String categories = 'categories';

  /// La langue de l'ouvrage.
  static const String language = 'language';

  /// L'ISBN de l'édition imprimée.
  static const String isbn = 'isbn';

  /// L'éditeur de l'ouvrage.
  static const String publisher = 'publisher';

  /// Le livre qui part chez Amazon.
  static const String projectId = 'project_id';
}

/// L'état d'un dépôt de publication.
///
/// L'état décrit ce qu'Amazon a répondu, jamais ce que la plateforme
/// suppose : un dossier préparé n'est pas déposé, et un dossier déposé
/// n'est pas encore publié.
enum KdpState {
  /// Le dossier est préparé et attend son dépôt.
  draft('draft'),

  /// Amazon a reçu le dossier : son verdict n'est pas encore connu, ou il
  /// l'a accepté.
  submitted('submitted'),

  /// Amazon a publié le livre.
  ///
  /// Le serveur ne suit pas encore cette étape : l'état est prévu pour elle,
  /// il n'est jamais produit par une lecture.
  live('live'),

  /// Amazon a refusé le dossier : le refus porte son motif.
  refused('refused'),

  /// Le dépôt a échoué : Amazon n'a pas répondu.
  failed('failed');

  const KdpState(this.key);

  /// Le nom technique de l'état.
  final String key;
}

/// La gravité d'un problème relevé sur un dossier de publication.
enum KdpIssueSeverity {
  /// Le problème empêche le dépôt : Amazon refusera le dossier.
  blocking,

  /// Le problème n'empêche pas le dépôt, mais l'auteur doit le connaître.
  warning,
}

/// Un problème relevé sur un dossier de publication.
///
/// Chaque problème nomme le champ fautif et ce qu'il faut corriger.
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

  /// Vrai quand le problème empêche le dépôt.
  bool get isBlocking => severity == KdpIssueSeverity.blocking;
}

/// Le motif d'un refus d'Amazon.
///
/// Le motif porte les problèmes qu'Amazon a donnés, et le motif d'un échec
/// technique quand le dossier n'a pas pu partir. Les deux sont montrés à
/// l'auteur : il doit savoir ce qu'il doit corriger.
final class KdpRefusal {
  /// Crée un motif de refus.
  const KdpRefusal({this.issues = const <KdpIssue>[], this.reason});

  /// Les problèmes relevés par Amazon.
  final List<KdpIssue> issues;

  /// Le motif d'un échec technique, `null` quand Amazon a répondu.
  final String? reason;

  /// Vrai quand le motif ne dit rien.
  bool get isEmpty => issues.isEmpty && (reason == null || reason!.isEmpty);
}

/// L'ISBN de l'édition imprimée.
///
/// Amazon exige un code valide : dix ou treize chiffres, avec sa clé de
/// contrôle. Le fichier préparé porte l'ISBN sans tiret ni espace.
abstract final class KdpIsbn {
  /// Normalise [raw] en ISBN sans tiret ni espace.
  static String normalize(String raw) => raw.replaceAll(RegExp(r'[\s-]'), '');

  /// Vrai quand [isbn] porte une clé de contrôle valide.
  ///
  /// Le code est donné sans tiret ni espace : [normalize] le prépare.
  static bool isValid(String isbn) {
    if (isbn.length == 13) return _isValidIsbn13(isbn);
    if (isbn.length == 10) return _isValidIsbn10(isbn);
    return false;
  }

  static final RegExp _isbn13 = RegExp(r'^\d{13}$');

  static final RegExp _isbn10 = RegExp(r'^\d{9}[\dXx]$');

  static bool _isValidIsbn13(String isbn) {
    if (!_isbn13.hasMatch(isbn)) return false;
    var sum = 0;
    for (var index = 0; index < 12; index++) {
      final int digit = int.parse(isbn[index]);
      sum += index.isEven ? digit : digit * 3;
    }
    final int check = (10 - (sum % 10)) % 10;
    return check == int.parse(isbn[12]);
  }

  static bool _isValidIsbn10(String isbn) {
    if (!_isbn10.hasMatch(isbn)) return false;
    var sum = 0;
    for (var index = 0; index < 10; index++) {
      final String character = isbn[index];
      final int value = character.toUpperCase() == 'X'
          ? 10
          : int.parse(character);
      sum += value * (10 - index);
    }
    return sum % 11 == 0;
  }
}

/// La raison pour laquelle un champ est refusé.
enum KdpFieldErrorReason {
  /// Le champ est vide.
  empty,

  /// L'ISBN ne porte pas une clé de contrôle valide.
  malformedIsbn,
}

/// Un champ fautif, nommé.
///
/// Le champ est nommé : l'auteur sait ce qu'il doit corriger, sans lire le
/// journal du serveur.
final class KdpFieldError {
  /// Crée une erreur de champ.
  const KdpFieldError({required this.field, required this.reason});

  /// Le nom du champ fautif.
  final String field;

  /// La raison du refus.
  final KdpFieldErrorReason reason;
}

/// Les métadonnées que la fiche produit d'Amazon exige.
///
/// Les métadonnées viennent de l'auteur : la plateforme ne les invente pas,
/// elle les contrôle. Le titre porte le sous-titre, comme Amazon le fait
/// dans sa fiche produit : le serveur ne garde qu'un titre.
final class KdpMetadata {
  /// Crée un ensemble de métadonnées.
  const KdpMetadata({
    required this.title,
    required this.author,
    this.subtitle = '',
    this.description = '',
    this.keywords = const <String>[],
    this.categories = const <String>[],
    this.language = '',
    this.isbn = '',
    this.publisher = '',
  });

  /// Le titre de l'ouvrage.
  final String title;

  /// Le sous-titre de l'ouvrage.
  final String subtitle;

  /// Le nom de l'auteur.
  final String author;

  /// Le résumé de l'ouvrage.
  final String description;

  /// Les sept mots-clés de la fiche produit.
  final List<String> keywords;

  /// Les trois catégories BISAC de la fiche produit.
  final List<String> categories;

  /// La langue de l'ouvrage.
  final String language;

  /// L'ISBN de l'édition imprimée.
  final String isbn;

  /// L'éditeur de l'ouvrage.
  final String publisher;

  /// Le titre porté par la fiche produit.
  ///
  /// Le sous-titre y est joint : c'est la forme que la fiche d'Amazon
  /// attend, et la seule que le serveur garde.
  String get composedTitle {
    final String main = title.trim();
    final String rest = subtitle.trim();
    if (rest.isEmpty) return main;
    if (main.isEmpty) return rest;
    return '$main: $rest';
  }

  /// L'ISBN normalisé : sans tiret ni espace.
  String get normalizedIsbn => KdpIsbn.normalize(isbn.trim());

  /// Le champ fautif des métadonnées, `null` quand elles sont acceptables.
  ///
  /// Le contrôle porte ce que l'auteur corrige sans le serveur : le titre,
  /// le nom de l'auteur et l'ISBN. Le serveur contrôle le reste — la
  /// longueur du résumé, le nombre de mots-clés — et répond un message qui
  /// nomme le champ.
  KdpFieldError? validate() {
    if (title.trim().isEmpty) {
      return const KdpFieldError(
        field: KdpFields.title,
        reason: KdpFieldErrorReason.empty,
      );
    }
    if (author.trim().isEmpty) {
      return const KdpFieldError(
        field: KdpFields.author,
        reason: KdpFieldErrorReason.empty,
      );
    }
    if (isbn.trim().isEmpty) {
      return const KdpFieldError(
        field: KdpFields.isbn,
        reason: KdpFieldErrorReason.empty,
      );
    }
    if (!KdpIsbn.isValid(normalizedIsbn)) {
      return const KdpFieldError(
        field: KdpFields.isbn,
        reason: KdpFieldErrorReason.malformedIsbn,
      );
    }
    return null;
  }

  /// Une copie des métadonnées avec les champs remplacés.
  KdpMetadata copyWith({
    String? title,
    String? subtitle,
    String? author,
    String? description,
    List<String>? keywords,
    List<String>? categories,
    String? language,
    String? isbn,
    String? publisher,
  }) {
    return KdpMetadata(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      author: author ?? this.author,
      description: description ?? this.description,
      keywords: keywords ?? this.keywords,
      categories: categories ?? this.categories,
      language: language ?? this.language,
      isbn: isbn ?? this.isbn,
      publisher: publisher ?? this.publisher,
    );
  }
}

/// La marque d'un champ que la copie d'un dépôt ne remplace pas.
///
/// La marque distingue « le champ est absent de la copie » de « le champ
/// est présent et vide » : un dépôt repris efface ainsi le motif du refus
/// précédent.
const Object _unset = Object();

/// Un dépôt de publication chez Amazon KDP.
///
/// La trace porte ce qui a été préparé — le livre, les métadonnées, le
/// résultat du contrôle — et ce qu'Amazon a répondu : l'état du dépôt et
/// le motif d'un refus.
final class KdpSubmission {
  /// Crée un dépôt.
  const KdpSubmission({
    required this.id,
    required this.projectId,
    required this.title,
    required this.author,
    required this.description,
    required this.keywords,
    required this.categories,
    required this.language,
    required this.publisher,
    required this.isbn,
    required this.state,
    required this.isReady,
    required this.issues,
    required this.wordCount,
    required this.pageCount,
    required this.createdAt,
    this.refusal,
    this.depositId,
    this.amazonSubmissionId,
    this.attempts = 0,
    this.updatedAt,
  });

  /// L'identifiant de la publication.
  final String id;

  /// Le projet publié.
  final String projectId;

  /// Le titre de l'ouvrage.
  final String title;

  /// Le nom de l'auteur.
  final String author;

  /// Le résumé de l'ouvrage.
  final String description;

  /// Les mots-clés de la fiche produit.
  final List<String> keywords;

  /// Les catégories BISAC de la fiche produit.
  final List<String> categories;

  /// La langue de l'ouvrage.
  final String language;

  /// L'éditeur de l'ouvrage.
  final String publisher;

  /// L'ISBN de l'édition imprimée.
  final String? isbn;

  /// L'état du dépôt.
  final KdpState state;

  /// Vrai quand le dossier passe le contrôle de soumission.
  final bool isReady;

  /// Les problèmes relevés par le contrôle de soumission.
  final List<KdpIssue> issues;

  /// Le motif d'un refus d'Amazon, `null` quand le dossier n'a pas été
  /// refusé.
  final KdpRefusal? refusal;

  /// Le nombre de mots du livre.
  final int wordCount;

  /// Le nombre de pages du PDF d'impression.
  final int pageCount;

  /// L'horodatage de la préparation.
  final DateTime createdAt;

  /// L'identifiant du dépôt, `null` quand le dossier n'a jamais été déposé.
  final String? depositId;

  /// L'identifiant du dépôt chez Amazon, `null` tant qu'Amazon n'a pas
  /// accepté le dossier.
  final String? amazonSubmissionId;

  /// Le nombre de tentatives faites auprès d'Amazon.
  final int attempts;

  /// L'horodatage du dernier changement d'état.
  final DateTime? updatedAt;

  /// Les problèmes qui empêchent le dépôt.
  List<KdpIssue> get blockingIssues => List<KdpIssue>.unmodifiable(
    issues.where((KdpIssue issue) => issue.isBlocking),
  );

  /// Vrai quand le dossier peut être déposé auprès d'Amazon.
  ///
  /// Un dossier que le contrôle a bloqué ne part pas, et un dossier déjà
  /// accepté ne part jamais deux fois.
  bool get canDeposit => state != KdpState.submitted && isReady;

  /// Une copie du dépôt avec les champs remplacés.
  ///
  /// Les champs absents de [copyWith] gardent leur valeur : le dépôt n'est
  /// jamais modifié en place. Les champs facultatifs se vident quand on leur
  /// passe explicitement `null`.
  KdpSubmission copyWith({
    String? title,
    String? author,
    String? description,
    List<String>? keywords,
    List<String>? categories,
    String? language,
    String? publisher,
    Object? isbn = _unset,
    KdpState? state,
    bool? isReady,
    List<KdpIssue>? issues,
    Object? refusal = _unset,
    int? wordCount,
    int? pageCount,
    Object? depositId = _unset,
    Object? amazonSubmissionId = _unset,
    int? attempts,
    Object? updatedAt = _unset,
  }) {
    return KdpSubmission(
      id: id,
      projectId: projectId,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      keywords: keywords ?? this.keywords,
      categories: categories ?? this.categories,
      language: language ?? this.language,
      publisher: publisher ?? this.publisher,
      isbn: identical(isbn, _unset) ? this.isbn : isbn as String?,
      state: state ?? this.state,
      isReady: isReady ?? this.isReady,
      issues: issues ?? this.issues,
      refusal: identical(refusal, _unset)
          ? this.refusal
          : refusal as KdpRefusal?,
      wordCount: wordCount ?? this.wordCount,
      pageCount: pageCount ?? this.pageCount,
      createdAt: createdAt,
      depositId: identical(depositId, _unset)
          ? this.depositId
          : depositId as String?,
      amazonSubmissionId: identical(amazonSubmissionId, _unset)
          ? this.amazonSubmissionId
          : amazonSubmissionId as String?,
      attempts: attempts ?? this.attempts,
      updatedAt: identical(updatedAt, _unset)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }
}

/// Le port de la publication d'un livre chez Amazon KDP.
///
/// L'écran de publication lit ce port et n'atteint jamais le serveur. La
/// doublure par défaut refuse les appels et dit pourquoi : un écran ne
/// présente jamais un dépôt qu'il n'a pas lu.
abstract interface class KdpRepository {
  /// Les dépôts du compte, les plus récents d'abord.
  Future<List<KdpSubmission>> list();

  /// Le dépôt [submissionId] du compte, `null` quand il n'existe pas.
  Future<KdpSubmission?> find(String submissionId);

  /// Prépare le dossier de publication d'un livre.
  ///
  /// Le serveur reconstruit le livre, produit les fichiers et contrôle le
  /// dossier : le dépôt rendu porte les problèmes à corriger.
  Future<KdpSubmission> prepare({
    required String projectId,
    required KdpMetadata metadata,
  });

  /// Dépose le dossier [submissionId] auprès d'Amazon.
  ///
  /// Lève [KdpUnavailableException] quand le dépôt est impossible sur ce
  /// poste : l'écran le dit, il ne prétend jamais que le livre est arrivé.
  Future<KdpSubmission> deposit({required String submissionId});
}

/// Le dépôt est impossible sur ce poste.
///
/// Le serveur ne connaît pas l'intégration Amazon, ou Amazon ne répond pas :
/// le livre n'est pas parti, et l'écran doit le dire.
final class KdpUnavailableException implements Exception {
  /// Crée l'exception.
  const KdpUnavailableException({this.reason});

  /// La raison donnée par le serveur, quand il en donne une.
  final String? reason;

  @override
  String toString() => 'KdpUnavailableException(${reason ?? 'not configured'})';
}

/// Les métadonnées sont refusées avant l'envoi.
final class KdpValidationException implements Exception {
  /// Crée l'exception.
  const KdpValidationException(this.error);

  /// Le champ fautif.
  final KdpFieldError error;

  @override
  String toString() => 'KdpValidationException(${error.field})';
}

/// Un [KdpRepository] qui ne peut pas atteindre le serveur.
///
/// Le mode démonstration n'a pas de service distant : l'écran de publication
/// le dit au lieu de montrer un dépôt qu'il n'a jamais lu.
final class UnavailableKdpRepository
    implements KdpRepository, UnavailableService {
  /// Crée le dépôt.
  const UnavailableKdpRepository();

  @override
  Future<List<KdpSubmission>> list() async =>
      throw const ServiceUnavailableException();

  @override
  Future<KdpSubmission?> find(String submissionId) async =>
      throw const ServiceUnavailableException();

  @override
  Future<KdpSubmission> prepare({
    required String projectId,
    required KdpMetadata metadata,
  }) async => throw const ServiceUnavailableException();

  @override
  Future<KdpSubmission> deposit({required String submissionId}) async =>
      throw const ServiceUnavailableException();
}

/// Le port de la publication Amazon KDP.
///
/// Le point de composition de l'application remplace ce doublure par
/// l'implémentation de la couche données. La doublure refuse et dit
/// pourquoi : un écran ne présente jamais un dépôt qu'il n'a pas lu.
final Provider<KdpRepository> kdpRepositoryProvider = Provider<KdpRepository>((
  Ref ref,
) {
  return const UnavailableKdpRepository();
});
