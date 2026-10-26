import '../errors/app_exception.dart';
import '../http/json_body.dart';
import 'kdp_isbn.dart';

/// Les règles qu'Amazon applique aux métadonnées d'une fiche produit.
///
/// Les valeurs viennent des consignes de publication d'Amazon : le titre
/// tient dans 200 caractères, le nom de l'auteur dans 250, le résumé dans
/// 4 000, la fiche accepte sept mots-clés de 50 caractères et trois
/// catégories.
abstract final class KdpMetadataRules {
  /// La longueur maximale du titre, sous-titre compris.
  static const int maxTitleLength = 200;

  /// La longueur maximale du nom de l'auteur.
  static const int maxAuthorLength = 250;

  /// La longueur maximale du résumé.
  static const int maxDescriptionLength = 4000;

  /// Le nombre de mots-clés que la fiche produit accepte.
  static const int maxKeywords = 7;

  /// La longueur maximale d'un mot-clé.
  static const int maxKeywordLength = 50;

  /// Le nombre de catégories que la fiche produit accepte.
  static const int maxCategories = 3;

  /// La longueur maximale du nom d'une catégorie.
  static const int maxCategoryLength = 100;

  /// La longueur maximale de l'ISBN, tirets et espaces compris.
  static const int maxIsbnLength = 17;

  /// Les caractères qu'Amazon refuse dans les métadonnées.
  ///
  /// Un caractère de contrôle s'affiche corrompu dans la fiche produit :
  /// Amazon refuse le titre qui en porte un. Les caractères invisibles
  /// (espace fine insécable, marque de paragraphe inversée) sont de même
  /// refusés, pour la même raison.
  static final RegExp forbiddenCharacters = RegExp(
    r'[\u0000-\u001F\u007F​-‍⁠﻿�]',
  );

  /// Le balisage que la fiche produit refuse dans le résumé.
  ///
  /// Amazon refuse une description qui porte du balisage : elle
  /// s'afficherait telle quelle dans la fiche.
  static final RegExp forbiddenMarkup = RegExp(r'<[a-zA-Z/!?][^>]*>|<<|>>|<>');
}

/// Les métadonnées qu'Amazon exige pour un livre.
///
/// Les métadonnées viennent de l'appelant : la plateforme ne les invente
/// pas, elle les valide. Une description ou un résumé absent n'empêche pas
/// la préparation, le contrôle de soumission le signale.
final class KdpMetadata {
  /// Crée un ensemble de métadonnées.
  const KdpMetadata({
    required this.title,
    required this.author,
    this.description = '',
    this.keywords = const <String>[],
    this.categories = const <String>[],
    this.isbn,
    this.language,
    this.publisher,
  });

  /// Le titre de l'ouvrage.
  final String title;

  /// Le nom de l'auteur.
  final String author;

  /// Le résumé de l'ouvrage.
  final String description;

  /// Les sept mots-clés de la fiche produit.
  final List<String> keywords;

  /// Les trois catégories de la fiche produit.
  final List<String> categories;

  /// L'ISBN de l'édition imprimée, sans tiret ni espace.
  final String? isbn;

  /// La langue de l'ouvrage, `null` quand celle du projet fait foi.
  final String? language;

  /// L'éditeur de l'ouvrage.
  final String? publisher;
}

/// La lecture et la validation des métadonnées d'une publication.
///
/// Chaque refus nomme le champ fautif : l'appelant sait ainsi ce qu'il
/// doit corriger, sans lire le journal du serveur.
abstract final class KdpMetadataReader {
  /// Lit les métadonnées du corps [body].
  ///
  /// Jette une [ValidationException] qui nomme le champ fautif quand une
  /// valeur dépasse sa longueur maximale, porte un caractère qu'Amazon
  /// refuse, ou n'est pas un ISBN valide.
  static KdpMetadata read(JsonBody body) {
    final String title = _text(
      body,
      'title',
      maxLength: KdpMetadataRules.maxTitleLength,
    );
    final String author = _text(
      body,
      'author',
      maxLength: KdpMetadataRules.maxAuthorLength,
    );
    final String description =
        _optionalText(
          body,
          'description',
          maxLength: KdpMetadataRules.maxDescriptionLength,
        ) ??
        '';
    _rejectMarkup(description, 'description');
    final String? isbn = _isbn(body);
    final String? publisher = _optionalText(
      body,
      'publisher',
      maxLength: KdpMetadataRules.maxAuthorLength,
    );
    final String? language = _optionalText(body, 'language', maxLength: 16);

    return KdpMetadata(
      title: title,
      author: author,
      description: description,
      keywords: _stringList(
        body,
        'keywords',
        maxItems: KdpMetadataRules.maxKeywords,
        maxLength: KdpMetadataRules.maxKeywordLength,
      ),
      categories: _stringList(
        body,
        'categories',
        maxItems: KdpMetadataRules.maxCategories,
        maxLength: KdpMetadataRules.maxCategoryLength,
      ),
      isbn: isbn,
      language: language,
      publisher: publisher,
    );
  }

  /// Lit un champ texte obligatoire, après avoir vérifié sa longueur et
  /// ses caractères.
  static String _text(JsonBody body, String field, {required int maxLength}) {
    final String value = body.requireString(field, maxLength: maxLength);
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ValidationException(
        field: field,
        message: 'Le champ « $field » ne peut pas être vide.',
      );
    }
    _rejectForbiddenCharacters(trimmed, field);
    return trimmed;
  }

  /// Lit un champ texte facultatif, `null` quand il est absent ou vide.
  static String? _optionalText(
    JsonBody body,
    String field, {
    required int maxLength,
  }) {
    final String? value = body.optionalString(field, maxLength: maxLength);
    if (value == null) return null;
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    _rejectForbiddenCharacters(trimmed, field);
    return trimmed;
  }

  /// Lit l'ISBN de l'édition imprimée et en vérifie la clé de contrôle.
  static String? _isbn(JsonBody body) {
    final String? raw = body.optionalString(
      'isbn',
      maxLength: KdpMetadataRules.maxIsbnLength,
    );
    if (raw == null) return null;
    final String normalized = KdpIsbn.normalize(raw);
    if (!KdpIsbn.isValid(normalized)) {
      throw ValidationException(
        field: 'isbn',
        message:
            'Le champ « isbn » ne porte pas un ISBN valide : Amazon exige '
            'un code à dix ou treize chiffres avec sa clé de contrôle.',
      );
    }
    return normalized;
  }

  /// Lit une liste de textes, en vérifiant le nombre et la longueur de
  /// chaque valeur.
  static List<String> _stringList(
    JsonBody body,
    String field, {
    required int maxItems,
    required int maxLength,
  }) {
    if (body.fields[field] == null) return const <String>[];
    final List<dynamic> values = body.requireList(field, maxLength: maxItems);
    final List<String> items = <String>[];
    for (final dynamic value in values) {
      if (value is! String) {
        throw ValidationException(
          field: field,
          message:
              'Le champ « $field » ne peut contenir que des chaînes de '
              'caractères.',
        );
      }
      final String trimmed = value.trim();
      if (trimmed.isEmpty) {
        throw ValidationException(
          field: field,
          message: 'Le champ « $field » ne peut pas contenir de valeur vide.',
        );
      }
      if (trimmed.length > maxLength) {
        throw ValidationException(
          field: field,
          message:
              'Le champ « $field » ne doit pas contenir de valeur de plus '
              'de $maxLength caractères.',
        );
      }
      _rejectForbiddenCharacters(trimmed, field);
      items.add(trimmed);
    }
    return List<String>.unmodifiable(items);
  }

  /// Refuse les caractères qu'Amazon ne tolère pas dans [value].
  static void _rejectForbiddenCharacters(String value, String field) {
    if (!KdpMetadataRules.forbiddenCharacters.hasMatch(value)) return;
    throw ValidationException(
      field: field,
      message:
          'Le champ « $field » porte un caractère qu\'Amazon refuse dans '
          'une fiche produit.',
    );
  }

  /// Refuse le balisage du résumé.
  static void _rejectMarkup(String value, String field) {
    if (!KdpMetadataRules.forbiddenMarkup.hasMatch(value)) return;
    throw ValidationException(
      field: field,
      message:
          'Le champ « $field » ne peut pas porter de balisage : Amazon '
          'refuse une description qui contient des balises.',
    );
  }
}
