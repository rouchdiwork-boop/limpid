import '../util/xml_writer.dart';

/// Generateur du manifeste `META-INF/manifest.xml` d'un paquet ODT.
class OdtManifestXml {
  const OdtManifestXml();

  /// Namespace du manifeste ODF.
  static const String manifestNamespace =
      'urn:oasis:names:tc:opendocument:xmlns:manifest:1.0';

  /// Serialise le manifeste.
  ///
  /// [entries] associe un chemin interne a son type MIME.
  String render(Map<String, String> entries) {
    final writer = XmlWriter();
    writer.namespacedElement(
      'manifest:manifest',
      namespaces: <String, String>{manifestNamespace: 'manifest'},
      attributes: <String, String>{'manifest:version': '1.3'},
      nest: () {
        writer.namespacedElement(
          'manifest:file-entry',
          attributes: <String, String>{
            'manifest:full-path': '/',
            'manifest:version': '1.3',
            'manifest:media-type': 'application/vnd.oasis.opendocument.text',
          },
        );
        for (final entry in entries.entries) {
          writer.namespacedElement(
            'manifest:file-entry',
            attributes: <String, String>{
              'manifest:full-path': entry.key,
              'manifest:media-type': entry.value,
            },
          );
        }
      },
    );
    return writer.toXmlString();
  }
}
