import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_app/src/features/projects/project_cover.dart';
import 'package:limpid_app/src/features/publication/publication_cover.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// The cover the server renders for a book: a small, valid SVG document.
const String coverSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="150" '
    'viewBox="0 0 100 150"><rect width="100" height="150" fill="#7a4a2f"/>'
    '</svg>';

void main() {
  /// Enveloppe la couverture dans le thème qu'elle lui faut.
  Widget harness(Widget child) {
    return MaterialApp(
      theme: LimpidTheme.of(LimpidThemeVariant.paper),
      home: Scaffold(body: child),
    );
  }

  group('la couverture d’un livre public', () {
    testWidgets('montre l’artefact du serveur quand le livre en a un', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          PublicationCover(
            title: 'Les Heures de Cendre',
            author: 'Aurélien Sandre',
            seed: 1,
            url: 'https://api.test/v1/public/books/heures/cover',
            width: 120,
            loader: (String url) async =>
                Uint8List.fromList(coverSvg.codeUnits),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(ProjectCover), findsNothing);
    });

    testWidgets('montre son propre fond quand le livre n’en a pas', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          const PublicationCover(
            title: 'Les Heures de Cendre',
            author: 'Aurélien Sandre',
            seed: 1,
            width: 120,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProjectCover), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('montre son propre fond quand le serveur ne rend rien', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          PublicationCover(
            title: 'Les Heures de Cendre',
            author: 'Aurélien Sandre',
            seed: 1,
            url: 'https://api.test/v1/public/books/heures/cover',
            width: 120,
            loader: (String url) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProjectCover), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });
  });
}
