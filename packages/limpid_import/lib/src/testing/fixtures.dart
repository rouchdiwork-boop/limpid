import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Un PNG d'un pixel, encode en base64.
///
/// L'image sert de fixture : un DOCX qui declare une image doit l'annoncer
/// comme laissee de cote.
const String onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
    'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// Le contenu XML d'un `document.xml` Word.
const String docxDocumentXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
      <w:r><w:t>Le titre</w:t></w:r>
    </w:p>
    <w:p><w:r><w:t>Un paragraphe.</w:t></w:r></w:p>
    <w:p>
      <w:pPr><w:pStyle w:val="Heading2"/></w:pPr>
      <w:r><w:t>Premier chapitre</w:t></w:r>
    </w:p>
    <w:p><w:r><w:t>Le texte du chapitre.</w:t></w:r></w:p>
    <w:p>
      <w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr>
      <w:r><w:t>Un element de liste</w:t></w:r>
    </w:p>
    <w:p><w:r><w:br w:type="page"/></w:r></w:p>
    <w:p><w:r><w:t>La suite de la scene.</w:t></w:r></w:p>
    <w:sectPr/>
  </w:body>
</w:document>
''';

/// Le contenu XML des styles d'un document Word.
const String docxStylesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
  </w:style>
</w:styles>
''';

/// Le contenu XML de la numerotation des listes d'un document Word.
const String docxNumberingXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0">
    <w:lvl w:ilvl="0">
      <w:numFmt w:val="bullet"/>
    </w:lvl>
  </w:abstractNum>
  <w:num w:numId="1">
    <w:abstractNumId w:val="0"/>
  </w:num>
</w:numbering>
''';

/// Le contenu XML des types d'un paquet OOXML.
const String docxContentTypesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>
''';

/// Le contenu XML des relations de la racine d'un paquet OOXML.
const String docxRootRelsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>
''';

/// Le contenu XML des relations du document Word.
const String docxDocumentRelsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
</Relationships>
''';

/// Le contenu XML des proprietes d'un document Word.
const String docxCoreXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:title>Le livre</dc:title>
</cp:coreProperties>
''';

/// Le contenu XML du corps d'un document OpenDocument.
const String odtContentXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
    xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
    xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
    xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
    office:version="1.2">
  <office:automatic-styles>
    <style:style style:name="Titre_20_1" style:family="paragraph">
      <style:paragraph-properties fo:outline-level="1"/>
    </style:style>
    <style:style style:name="Titre_20_2" style:family="paragraph">
      <style:paragraph-properties fo:outline-level="2"/>
    </style:style>
  </office:automatic-styles>
  <office:body>
    <office:text>
      <text:h text:style-name="Titre_20_1" text:outline-level="1">Le titre</text:h>
      <text:p>Un paragraphe.</text:p>
      <text:h text:style-name="Titre_20_2" text:outline-level="2">Premier chapitre</text:h>
      <text:p>Le texte du chapitre.</text:p>
      <text:list text:style-name="Liste_20_1">
        <text:list-item><text:p>Un element de liste</text:p></text:list-item>
        <text:list-item><text:p>Un autre element</text:p></text:list-item>
      </text:list>
    </office:text>
  </office:body>
</office:document-content>
''';

/// Le contenu XML des metadonnees d'un document OpenDocument.
const String odtMetaXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<office:document-meta
    xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0"
    office:version="1.2">
  <office:meta>
    <meta:title>Le livre</meta:title>
  </office:meta>
</office:document-meta>
''';

/// Le contenu XML du manifeste d'un paquet OpenDocument.
const String odtManifestXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="meta.xml" manifest:media-type="text/xml"/>
</manifest:manifest>
''';

/// Le contenu XML du conteneur d'un livre EPUB.
const String epubContainerXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

/// Le contenu XML du document OPF d'un livre EPUB.
const String epubOpfXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Le livre</dc:title>
    <dc:language>fr</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
''';

/// Le contenu XHTML du premier chapitre d'un livre EPUB.
const String epubChapterOneXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Premier chapitre</title></head>
  <body>
    <h1>Une section</h1>
    <p>Le texte de la section.</p>
    <h2>Une sous-section</h2>
    <p>Le texte de la sous-section.</p>
    <ul>
      <li>Un element de liste</li>
    </ul>
    <img src="image.png" alt="une image"/>
  </body>
</html>
''';

/// Le contenu XHTML du second chapitre d'un livre EPUB.
const String epubChapterTwoXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Second chapitre</title></head>
  <body>
    <p>Encore du texte.</p>
  </body>
</html>
''';

/// Le contenu XHTML de la table des matieres d'un livre EPUB.
const String epubNavXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Table des matieres</title></head>
  <body>
    <nav epub:type="toc">
      <ol>
        <li><a href="chapter1.xhtml">Premier chapitre</a></li>
      </ol>
    </nav>
  </body>
</html>
''';

/// Construit un paquet ZIP a partir de [entries].
///
/// Les entrees sont ecrites dans l'ordre : le premier octet d'un paquet ODT
/// ou EPUB doit etre l'entree `mimetype`.
Uint8List buildZip(List<MapEntry<String, List<int>>> entries) {
  final Archive archive = Archive();
  for (final MapEntry<String, List<int>> entry in entries) {
    final ArchiveFile file = ArchiveFile.bytes(entry.key, entry.value);
    archive.addFile(file);
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Construit un fichier DOCX valide.
///
/// Le paquet porte le corps du document, ses styles, sa numerotation, ses
/// proprietes et une image : l'import doit annoncer l'image laissee de
/// cote.
Uint8List buildDocx() {
  return buildZip(<MapEntry<String, List<int>>>[
    MapEntry<String, List<int>>(
      '[Content_Types].xml',
      utf8.encode(docxContentTypesXml),
    ),
    MapEntry<String, List<int>>('_rels/.rels', utf8.encode(docxRootRelsXml)),
    MapEntry<String, List<int>>(
      'word/_rels/document.xml.rels',
      utf8.encode(docxDocumentRelsXml),
    ),
    MapEntry<String, List<int>>(
      'word/document.xml',
      utf8.encode(docxDocumentXml),
    ),
    MapEntry<String, List<int>>('word/styles.xml', utf8.encode(docxStylesXml)),
    MapEntry<String, List<int>>(
      'word/numbering.xml',
      utf8.encode(docxNumberingXml),
    ),
    MapEntry<String, List<int>>('docProps/core.xml', utf8.encode(docxCoreXml)),
    MapEntry<String, List<int>>(
      'word/media/image1.png',
      base64Decode(onePixelPng),
    ),
  ]);
}

/// Construit un fichier ODT valide.
Uint8List buildOdt() {
  return buildZip(<MapEntry<String, List<int>>>[
    MapEntry<String, List<int>>(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.text'),
    ),
    MapEntry<String, List<int>>(
      'META-INF/manifest.xml',
      utf8.encode(odtManifestXml),
    ),
    MapEntry<String, List<int>>('content.xml', utf8.encode(odtContentXml)),
    MapEntry<String, List<int>>('meta.xml', utf8.encode(odtMetaXml)),
  ]);
}

/// Construit un livre EPUB valide.
Uint8List buildEpub() {
  return buildZip(<MapEntry<String, List<int>>>[
    MapEntry<String, List<int>>(
      'mimetype',
      utf8.encode('application/epub+zip'),
    ),
    MapEntry<String, List<int>>(
      'META-INF/container.xml',
      utf8.encode(epubContainerXml),
    ),
    MapEntry<String, List<int>>('OEBPS/content.opf', utf8.encode(epubOpfXml)),
    MapEntry<String, List<int>>('OEBPS/nav.xhtml', utf8.encode(epubNavXml)),
    MapEntry<String, List<int>>(
      'OEBPS/chapter1.xhtml',
      utf8.encode(epubChapterOneXml),
    ),
    MapEntry<String, List<int>>(
      'OEBPS/chapter2.xhtml',
      utf8.encode(epubChapterTwoXml),
    ),
  ]);
}
