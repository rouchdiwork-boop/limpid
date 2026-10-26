import 'dart:convert';

import '../db/kdp_record.dart';

/// La lecture du refus d'Amazon.
///
/// Amazon refuse un dossier en listant ce qui ne convient pas. La lecture
/// traduit cette liste dans la forme du contrôle de soumission : un
/// problème, un code, un champ et ce qu'il faut corriger.
///
/// Les messages d'Amazon sont écrits en anglais : la lecture les traduit
/// quand elle connaît le code, et les reprend tels quels dans une phrase
/// française quand elle ne le connaît pas. L'auteur voit toujours une
/// phrase qui dit quoi corriger.
///
/// Les textes repris d'Amazon sont bornés et échappés avant d'être
/// stockés : un message enorme ne gonfle pas la trace du dépôt, et un
/// message hostile ne devient pas une balise.
abstract final class KdpAmazonRefusal {
  /// Les messages français des refus que la lecture connaît.
  static const Map<String, String> messages = <String, String>{
    'isbn_already_in_use':
        "L'ISBN indiqué est déjà utilisé par un autre ouvrage.",
    'isbn_missing': "L'édition imprimée exige un ISBN.",
    'isbn_invalid': "L'ISBN indiqué n'est pas un ISBN valide.",
    'file_missing': "Amazon n'a pas reçu le fichier du livre.",
    'file_unreadable':
        "Amazon n'a pas pu lire le fichier du livre électronique.",
    'file_too_large':
        'Le fichier du livre dépasse la taille maximale acceptée par Amazon.',
    'content_not_readable': "Amazon n'a pas pu lire le contenu du livre.",
    'metadata_invalid':
        "Une donnée de la fiche produit n'a pas été acceptée par Amazon.",
    'metadata_too_long':
        'Une donnée de la fiche produit dépasse la longueur maximale '
        'acceptée par Amazon.',
    'title_missing': 'Amazon exige un titre pour la fiche produit.',
    'rights_not_owned': 'Amazon demande la preuve des droits sur le texte.',
    'account_not_verified':
        "Le compte Amazon qui dépose le dossier n'est pas encore vérifié.",
  };

  /// Le champ porté par un refus qu'Amazon ne rattache à aucun champ.
  static const String defaultField = 'manuscript';

  /// La longueur maximale du message d'Amazon recopié dans un problème.
  ///
  /// Le message d'Amazon peut être énorme : il est borné avant d'être
  /// stocké, pour qu'une réponse d'Amazon ne gonfle pas la trace du dépôt.
  /// La borne compte le préfixe français : le message entier, celui qui
  /// est stocké, ne dépasse jamais cette longueur.
  static const int maxMessageLength = 512;

  /// Le préfixe qui annonce le refus d'Amazon dans un message.
  ///
  /// Le préfixe n'est pas échappé : il est écrit par la plateforme, il ne
  /// porte rien de hostile.
  static const String refusalPrefix = 'Amazon a refusé le dépôt : ';

  /// La longueur maximale d'un code ou d'un champ recopié d'Amazon.
  static const int maxTokenLength = 64;

  /// Lit la liste des problèmes que porte la réponse de refus [body].
  ///
  /// La réponse vide ou illisible rend une liste qui explique qu'Amazon a
  /// refusé le dossier sans préciser la raison : l'auteur doit savoir que
  /// le dossier n'est pas passé, même quand Amazon ne l'a pas expliqué.
  static List<KdpIssue> read(String body) {
    final Object? decoded = _decode(body);
    if (decoded is! Map<String, dynamic>) {
      return <KdpIssue>[_unexplained()];
    }
    final List<Object?> entries = _entriesOf(decoded);
    if (entries.isEmpty) {
      return <KdpIssue>[_unexplained()];
    }
    final List<KdpIssue> issues = <KdpIssue>[];
    for (final Object? entry in entries) {
      final KdpIssue? issue = _readIssue(entry);
      if (issue != null) issues.add(issue);
    }
    if (issues.isEmpty) return <KdpIssue>[_unexplained()];
    return List<KdpIssue>.unmodifiable(issues);
  }

  /// Le problème qui dit qu'Amazon a refusé le dossier sans l'expliquer.
  static KdpIssue _unexplained() {
    return const KdpIssue(
      code: 'amazon_refused',
      field: defaultField,
      message:
          'Amazon a refusé le dossier sans préciser la raison. Relancez le '
          'dépôt après avoir vérifié la fiche produit.',
    );
  }

  /// La liste des problèmes de la réponse, selon la clé qu'Amazon a employée.
  static List<Object?> _entriesOf(Map<String, dynamic> decoded) {
    for (final String key in <String>['issues', 'errors', 'reasons']) {
      final Object? value = decoded[key];
      if (value is List) return value.cast<Object?>();
    }
    return const <Object?>[];
  }

  /// Traduit une entrée de refus en problème.
  ///
  /// Le code et le champ d'Amazon sont bornés et échappés comme le
  /// message : ils sont recopiés tels quels dans la trace du dépôt.
  static KdpIssue? _readIssue(Object? entry) {
    if (entry is! Map<String, dynamic>) return null;
    final Object? rawCode = entry['code'];
    final String code = rawCode is String && rawCode.trim().isNotEmpty
        ? rawCode.trim()
        : 'amazon_refused';
    final Object? rawField = entry['field'];
    final String field = rawField is String && rawField.trim().isNotEmpty
        ? rawField.trim()
        : defaultField;
    return KdpIssue(
      code: _bounded(code, maxTokenLength),
      field: _bounded(field, maxTokenLength),
      message: _messageOf(code, entry['message']),
      severity: _severityOf(entry['severity']),
    );
  }

  /// Le message français du refus [code].
  ///
  /// Un code inconnu reprend la raison d'Amazon : elle est plus utile à
  /// l'auteur qu'une phrase générique. Elle est bornée et échappée avant
  /// d'être stockée, et le message entier — préfixe compris — ne dépasse
  /// jamais [maxMessageLength] caractères.
  static String _messageOf(String code, Object? raw) {
    final String? known = messages[code];
    if (known != null) return known;
    if (raw is String && raw.trim().isNotEmpty) {
      final String reason = _bounded(
        raw,
        maxMessageLength - refusalPrefix.length,
      );
      return '$refusalPrefix$reason';
    }
    return 'Amazon a refusé le dépôt sans préciser la raison.';
  }

  /// Le texte [raw] échappé et borné à [limit] caractères.
  ///
  /// Le texte est échappé caractère par caractère : il ne peut donc pas
  /// contenir de balise, et il n'est jamais coupé au milieu d'une
  /// entité. Un texte trop long est coupé et terminé par une ellipse, et
  /// le résultat ne dépasse jamais [limit] caractères.
  static String _bounded(String raw, int limit) {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in raw.trim().runes) {
      final String chunk = _escaped(rune);
      if (buffer.length + chunk.length > limit - 1) {
        buffer.write('…');
        break;
      }
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  /// Le caractère [rune] échappé pour l'affichage.
  static String _escaped(int rune) {
    switch (String.fromCharCode(rune)) {
      case '&':
        return '&amp;';
      case '<':
        return '&lt;';
      case '>':
        return '&gt;';
      case '"':
        return '&quot;';
      case "'":
        return '&#39;';
      default:
        return String.fromCharCode(rune);
    }
  }

  /// La gravité du refus, bloquante par défaut.
  static KdpIssueSeverity _severityOf(Object? value) {
    if (value is String) {
      for (final KdpIssueSeverity severity in KdpIssueSeverity.values) {
        if (severity.key == value) return severity;
      }
    }
    return KdpIssueSeverity.blocking;
  }

  static Object? _decode(String body) {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
