import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The four themes, in the order of the canonical table of
/// `docs/DESIGN_SYSTEM.md` §2.2.
const List<String> themes = <String>['paper', 'sepia', 'night', 'contrast'];

/// The canonical table, relative to the package.
const String designSystemPath = '../../docs/DESIGN_SYSTEM.md';

/// The mockups, relative to the package.
const String mockupsPath = '../../mockups/limpid-mockups.html';

/// Reads the canonical colour table of the design system document.
///
/// A row of the table looks like:
///
/// ```markdown
/// | `bgCanvas` | `#FAF8F4` | `#F4EBD8` | `#14110E` | `#000000` |
/// ```
///
/// The rows that do not follow that exact shape are ignored: the document
/// holds other tables whose columns are not colours.
Map<String, List<String>> parseCanonicalTable(String document) {
  final RegExp row = RegExp(
    r'^\|\s*`([A-Za-z][A-Za-z0-9]*)`\s*'
    r'\|\s*`(#[0-9A-Fa-f]{3,8})`\s*'
    r'\|\s*`(#[0-9A-Fa-f]{3,8})`\s*'
    r'\|\s*`(#[0-9A-Fa-f]{3,8})`\s*'
    r'\|\s*`(#[0-9A-Fa-f]{3,8})`\s*\|\s*$',
    multiLine: true,
  );

  final Map<String, List<String>> colors = <String, List<String>>{};
  for (final RegExpMatch match in row.allMatches(document)) {
    colors[match.group(1)!] = <String>[
      match.group(2)!,
      match.group(3)!,
      match.group(4)!,
      match.group(5)!,
    ];
  }
  return colors;
}

/// Reads the palette a theme declares in the mockups.
///
/// The mockups carry one CSS block per theme:
///
/// ```css
/// [data-product="paper"] { --p-bg-canvas:#FAF8F4; ... }
/// ```
Map<String, String> parseMockupPalette(String mockups, String theme) {
  final RegExp block = RegExp(
    r'\[data-product="' + theme + r'"\]\s*\{([^}]*)\}',
    dotAll: true,
  );
  final RegExpMatch? match = block.firstMatch(mockups);
  if (match == null) {
    return <String, String>{};
  }

  final RegExp declaration = RegExp(
    r'--p-([a-z0-9-]+)\s*:\s*(#[0-9A-Fa-f]{3,8})',
  );
  final Map<String, String> palette = <String, String>{};
  for (final RegExpMatch declarationMatch in declaration.allMatches(
    match.group(1)!,
  )) {
    palette[declarationMatch.group(1)!] = declarationMatch.group(2)!;
  }
  return palette;
}

/// Turns a kebab-case CSS name into the camelCase name of its token.
///
/// `bg-canvas` becomes `bgCanvas`.
String tokenName(String cssName) {
  final List<String> parts = cssName.split('-');
  return parts.first +
      parts
          .skip(1)
          .map(
            (String part) =>
                part.isEmpty ? part : part[0].toUpperCase() + part.substring(1),
          )
          .join();
}

void main() {
  late Map<String, dynamic> tokens;

  setUpAll(() {
    tokens =
        jsonDecode(File('tokens.json').readAsStringSync())
            as Map<String, dynamic>;
  });

  group('parité de la table canonique', () {
    late Map<String, List<String>> documented;

    setUpAll(() {
      final File file = File(designSystemPath);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'The canonical table is missing ($designSystemPath). The '
            'design system document is the source of truth of the colours.',
      );
      documented = parseCanonicalTable(file.readAsStringSync());
    });

    test('la table décrit les quatre thèmes', () {
      expect(documented, isNotEmpty);
      for (final MapEntry<String, List<String>> entry in documented.entries) {
        expect(
          entry.value,
          hasLength(themes.length),
          reason: 'The row of ${entry.key} does not carry the four themes.',
        );
      }
    });

    test('chaque couleur documentée a les mêmes valeurs dans tokens.json', () {
      documented.forEach((String token, List<String> values) {
        for (int index = 0; index < themes.length; index++) {
          final Map<String, dynamic> theme =
              tokens['colors'][themes[index]] as Map<String, dynamic>;
          expect(
            theme[token],
            isNotNull,
            reason: '$token is missing from the ${themes[index]} theme.',
          );
          expect(
            theme[token],
            values[index],
            reason:
                '$token differs between ${themes[index]} in the document '
                'and in tokens.json.',
          );
        }
      });
    });

    test('chaque couleur de tokens.json est documentée', () {
      final Set<String> documentedNames = documented.keys.toSet();
      for (final String theme in themes) {
        final Map<String, dynamic> values =
            tokens['colors'][theme] as Map<String, dynamic>;
        expect(
          values.keys.toSet(),
          documentedNames,
          reason:
              'The colours of the $theme theme and the canonical table '
              'have drifted apart.',
        );
      }
    });
  });

  group('parité des maquettes', () {
    late String mockups;

    setUpAll(() {
      final File file = File(mockupsPath);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'The mockups are missing ($mockupsPath). They carry the same '
            'palette as the design system.',
      );
      mockups = file.readAsStringSync();
    });

    test('chaque thème des maquettes porte la palette des tokens', () {
      for (final String theme in themes) {
        final Map<String, String> palette = parseMockupPalette(mockups, theme);
        expect(
          palette,
          isNotEmpty,
          reason: 'The $theme theme declares no colour in the mockups.',
        );

        final Map<String, dynamic> values =
            tokens['colors'][theme] as Map<String, dynamic>;
        palette.forEach((String cssName, String value) {
          final String token = tokenName(cssName);
          expect(
            values[token],
            isNotNull,
            reason: '$token is declared in the mockups but not a token.',
          );
          expect(
            values[token],
            value,
            reason:
                '$token differs between the $theme theme of the mockups '
                'and in tokens.json.',
          );
        });
      }
    });

    test('les maquettes déclarent toutes les couleurs de la surface', () {
      for (final String theme in themes) {
        final Map<String, String> palette = parseMockupPalette(mockups, theme);
        for (final String cssName in <String>[
          'bg-canvas',
          'bg-surface',
          'fg-default',
          'accent',
          'secondary',
        ]) {
          expect(
            palette.containsKey(cssName),
            isTrue,
            reason: 'The $theme theme of the mockups omits $cssName.',
          );
        }
      }
    });
  });
}
