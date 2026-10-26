import 'package:limpid_design_system/golden.dart';

/// Les familles de polices de l'application.
///
/// Les faces sont embarquees par l'application (D-13) : `flutter test` ne les
/// charge pas tout seul.
const Map<String, List<String>> kReferenceFonts = <String, List<String>>{
  'Fraunces': <String>['Fraunces-Regular.ttf', 'Fraunces-Bold.ttf'],
  'Instrument Sans': <String>[
    'InstrumentSans-Regular.ttf',
    'InstrumentSans-Bold.ttf',
  ],
  'Literata': <String>['Literata-Regular.ttf', 'Literata-Bold.ttf'],
  'IBM Plex Mono': <String>['IBMPlexMono-Regular.ttf', 'IBMPlexMono-Bold.ttf'],
};

/// Le dossier des polices de l'application.
const String kReferenceFontsDirectory = 'assets/fonts';

/// Charge les polices reelles dans le test.
///
/// Sans ce chargement, le temoin d'image dessine des **rectangles** a la
/// place du texte : l'image prouve la mise en page, mais plus la
/// typographie. Le temoin structurel, lui, n'en depend pas.
Future<void> loadReferenceFonts() async {
  await GoldenFonts.loadMaterialIcons();
  for (final MapEntry<String, List<String>> entry in kReferenceFonts.entries) {
    await GoldenFonts.loadFamily(
      entry.key,
      entry.value
          .map((String file) => '$kReferenceFontsDirectory/$file')
          .toList(growable: false),
    );
  }
}
