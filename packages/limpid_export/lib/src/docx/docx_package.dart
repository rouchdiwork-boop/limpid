import '../util/xml_writer.dart';

/// Relation entre deux parties d'un paquet OOXML.
class DocxRelationship {
  /// Cree une relation.
  const DocxRelationship({
    required this.id,
    required this.type,
    required this.target,
  });

  /// Identifiant de la relation (par exemple `rId1`).
  final String id;

  /// Type de relation (URI complete).
  final String type;

  /// Cible de la relation, relative a la partie courante.
  final String target;
}

/// Elements de structure d'un paquet DOCX (OOXML).
class DocxPackage {
  const DocxPackage._();

  /// Namespace WordprocessingML.
  static const String wordNamespace =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  /// Namespace des relations de document.
  static const String officeRelationships =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  /// Namespace des relations de paquet.
  static const String packageRelationships =
      'http://schemas.openxmlformats.org/package/2006/relationships';

  /// Namespace des types de contenu.
  static const String contentTypesNamespace =
      'http://schemas.openxmlformats.org/package/2006/content-types';

  /// Namespace des proprietes de document.
  static const String corePropertiesNamespace =
      'http://schemas.openxmlformats.org/package/2006/metadata/core-properties';

  /// Namespace des proprietes etendues.
  static const String extendedPropertiesNamespace =
      'http://schemas.openxmlformats.org/officeDocument/2006/extended-properties';

  /// Namespace DC.
  static const String dcNamespace = 'http://purl.org/dc/elements/1.1/';

  /// Namespace DCTerms.
  static const String dctermsNamespace = 'http://purl.org/dc/terms/';

  /// Namespace XSI.
  static const String xsiNamespace =
      'http://www.w3.org/2001/XMLSchema-instance';

  /// Type de relation vers `styles.xml`.
  static const String stylesRelation = '$officeRelationships/styles';

  /// Type de relation vers `numbering.xml`.
  static const String numberingRelation = '$officeRelationships/numbering';

  /// Type de relation vers `footnotes.xml`.
  static const String footnotesRelation = '$officeRelationships/footnotes';

  /// Type de relation vers une image.
  static const String imageRelation = '$officeRelationships/image';

  /// Serialise `[Content_Types].xml`.
  static String contentTypes({
    required bool hasImages,
    required bool hasFootnotes,
  }) {
    final writer = XmlWriter();
    writer.element(
      'Types',
      attributes: <String, String>{'xmlns': contentTypesNamespace},
      nest: () {
        writer.element(
          'Default',
          attributes: <String, String>{
            'Extension': 'rels',
            'ContentType':
                'application/vnd.openxmlformats-package.relationships+xml',
          },
        );
        writer.element(
          'Default',
          attributes: <String, String>{
            'Extension': 'xml',
            'ContentType': 'application/xml',
          },
        );
        if (hasImages) {
          writer.element(
            'Default',
            attributes: <String, String>{
              'Extension': 'png',
              'ContentType': 'image/png',
            },
          );
          writer.element(
            'Default',
            attributes: <String, String>{
              'Extension': 'jpeg',
              'ContentType': 'image/jpeg',
            },
          );
        }
        writer.element(
          'Override',
          attributes: <String, String>{
            'PartName': '/word/document.xml',
            'ContentType':
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml',
          },
        );
        writer.element(
          'Override',
          attributes: <String, String>{
            'PartName': '/word/styles.xml',
            'ContentType':
                'application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml',
          },
        );
        writer.element(
          'Override',
          attributes: <String, String>{
            'PartName': '/word/numbering.xml',
            'ContentType':
                'application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml',
          },
        );
        if (hasFootnotes) {
          writer.element(
            'Override',
            attributes: <String, String>{
              'PartName': '/word/footnotes.xml',
              'ContentType':
                  'application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml',
            },
          );
        }
        writer.element(
          'Override',
          attributes: <String, String>{
            'PartName': '/docProps/core.xml',
            'ContentType':
                'application/vnd.openxmlformats-package.core-properties+xml',
          },
        );
        writer.element(
          'Override',
          attributes: <String, String>{
            'PartName': '/docProps/app.xml',
            'ContentType':
                'application/vnd.openxmlformats-officedocument.extended-properties+xml',
          },
        );
      },
    );
    return writer.toXmlString();
  }

  /// Serialise `_rels/.rels`.
  static String rootRelationships() {
    final writer = XmlWriter();
    writer.element(
      'Relationships',
      attributes: <String, String>{'xmlns': packageRelationships},
      nest: () {
        writer.element(
          'Relationship',
          attributes: <String, String>{
            'Id': 'rId1',
            'Type': '$officeRelationships/officeDocument',
            'Target': 'word/document.xml',
          },
        );
        writer.element(
          'Relationship',
          attributes: <String, String>{
            'Id': 'rId2',
            'Type':
                'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties',
            'Target': 'docProps/core.xml',
          },
        );
        writer.element(
          'Relationship',
          attributes: <String, String>{
            'Id': 'rId3',
            'Type': '$officeRelationships/extended-properties',
            'Target': 'docProps/app.xml',
          },
        );
      },
    );
    return writer.toXmlString();
  }

  /// Serialise `word/_rels/document.xml.rels`.
  static String documentRelationships(List<DocxRelationship> relationships) {
    final writer = XmlWriter();
    writer.element(
      'Relationships',
      attributes: <String, String>{'xmlns': packageRelationships},
      nest: () {
        for (final relationship in relationships) {
          writer.element(
            'Relationship',
            attributes: <String, String>{
              'Id': relationship.id,
              'Type': relationship.type,
              'Target': relationship.target,
            },
          );
        }
      },
    );
    return writer.toXmlString();
  }
}
