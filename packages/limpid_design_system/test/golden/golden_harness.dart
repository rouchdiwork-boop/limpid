import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limpid_design_system/golden.dart';
import 'package:limpid_design_system/limpid_design_system.dart';

/// La cle de la frontiere qui porte l'image du temoin.
///
/// L'image est capturee sur cette frontiere : elle contient le widget sous
/// test et rien d'autre.
const Key kGoldenBoundaryKey = Key('limpid-golden-boundary');

/// Les quatre themes couverts par les temoins, dans l'ordre du design
/// systeme.
const List<LimpidThemeVariant> kGoldenVariants = <LimpidThemeVariant>[
  LimpidThemeVariant.paper,
  LimpidThemeVariant.sepia,
  LimpidThemeVariant.night,
  LimpidThemeVariant.contrast,
];

/// Les noms des quatre themes, dans le meme ordre.
List<String> get kGoldenVariantNames => kGoldenVariants
    .map((LimpidThemeVariant variant) => variant.name)
    .toList(growable: false);

/// Le repertoire des attentes structurelles.
Directory get kGoldenExpectationDirectory => Directory('test/expectations');

/// Le fichier d'attente d'un widget.
File goldenExpectationFile(String name) =>
    File('${kGoldenExpectationDirectory.path}/$name.txt');

/// Un widget du design system couvert par un temoin.
@immutable
class GoldenSubject {
  /// Cree un sujet.
  const GoldenSubject({required this.name, required this.build});

  /// Le nom du widget : il donne le nom du fichier d'attente.
  final String name;

  /// Construit le widget sous test.
  ///
  /// La cle permet de retrouver le widget dans l'arbre rendu : la description
  /// commence exactement sur lui.
  final Widget Function(Key key) build;
}

/// Rends le widget sous test dans une application de test.
///
/// Le rendu est tenu dans une frontiere de repetition : l'image du temoin
/// d'image est capturee sur elle, et la description structurelle commence
/// sur le widget lui-meme.
Future<Key> pumpGoldenSubject(
  WidgetTester tester, {
  required GoldenSubject subject,
  required LimpidThemeVariant variant,
}) async {
  final Key subjectKey = UniqueKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: LimpidTheme.of(variant),
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: kGoldenBoundaryKey,
            child: subject.build(subjectKey),
          ),
        ),
      ),
    ),
  );
  // Deux images : la premiere pose l'arbre, la seconde regle les etats
  // transitoires. `pumpAndSettle` ne convient pas : les indicateurs
  // d'activite ne s'arretent jamais.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  return subjectKey;
}

/// Compare le rendu d'un widget a son attente structurelle.
GoldenWitness checkGoldenSubject({
  required GoldenSubject subject,
  required LimpidThemeVariant variant,
  required List<String> actual,
  required bool isUpdating,
}) {
  return GoldenWitnessTool.check(
    file: goldenExpectationFile(subject.name),
    title: subject.name,
    section: variant.name,
    order: kGoldenVariantNames,
    actual: actual,
    isUpdating: isUpdating,
    regenerateCommand:
        'cd packages/limpid_design_system && flutter test --update-goldens',
  );
}
