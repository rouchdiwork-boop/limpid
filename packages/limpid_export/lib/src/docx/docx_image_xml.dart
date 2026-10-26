import '../model/export_image.dart';
import '../util/xml_writer.dart';
import 'docx_document_xml.dart';

/// Generateur du dessin d'une illustration Word (DrawingML).
class DocxImageXml {
  const DocxImageXml();

  /// Serialise le paragraphe contenant l'illustration.
  ///
  /// L'illustration est inseree en ligne (`wp:inline`), avec sa taille
  /// affichee exprimee en EMU.
  void write(
    XmlWriter writer, {
    required ExportImage image,
    required DocxImage described,
    required String description,
  }) {
    writer.element(
      'w:p',
      nest: () {
        writer.element(
          'w:r',
          nest: () {
            writer.element(
              'w:drawing',
              nest: () {
                writer.element(
                  'wp:inline',
                  attributes: <String, String>{
                    'distT': '0',
                    'distB': '0',
                    'distL': '0',
                    'distR': '0',
                  },
                  nest: () {
                    writer.element(
                      'wp:extent',
                      attributes: <String, String>{
                        'cx': '${described.widthEmu}',
                        'cy': '${described.heightEmu}',
                      },
                    );
                    writer.element(
                      'wp:docPr',
                      attributes: <String, String>{
                        'id': '${described.relationshipId.hashCode.abs()}',
                        'name': image.fileName ?? 'Illustration',
                        'descr': description,
                      },
                    );
                    writer.element(
                      'a:graphic',
                      nest: () {
                        writer.element(
                          'a:graphicData',
                          attributes: <String, String>{
                            'uri':
                                'http://schemas.openxmlformats.org/drawingml/2006/picture',
                          },
                          nest: () {
                            writer.element(
                              'pic:pic',
                              nest: () {
                                writer.element(
                                  'pic:nvPicPr',
                                  nest: () {
                                    writer.element(
                                      'pic:cNvPr',
                                      attributes: <String, String>{
                                        'id': '0',
                                        'name':
                                            image.fileName ?? 'Illustration',
                                      },
                                    );
                                    writer.element('pic:cNvPicPr');
                                  },
                                );
                                writer.element(
                                  'pic:blipFill',
                                  nest: () {
                                    writer.element(
                                      'a:blip',
                                      attributes: <String, String>{
                                        'r:embed': described.relationshipId,
                                      },
                                    );
                                    writer.element(
                                      'a:stretch',
                                      nest: () => writer.element('a:fillRect'),
                                    );
                                  },
                                );
                                writer.element(
                                  'pic:spPr',
                                  nest: () {
                                    writer.element(
                                      'a:xfrm',
                                      nest: () {
                                        writer.element(
                                          'a:off',
                                          attributes: <String, String>{
                                            'x': '0',
                                            'y': '0',
                                          },
                                        );
                                        writer.element(
                                          'a:ext',
                                          attributes: <String, String>{
                                            'cx': '${described.widthEmu}',
                                            'cy': '${described.heightEmu}',
                                          },
                                        );
                                      },
                                    );
                                    writer.element(
                                      'a:prstGeom',
                                      attributes: <String, String>{
                                        'prst': 'rect',
                                      },
                                      nest: () => writer.element('a:avLst'),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
