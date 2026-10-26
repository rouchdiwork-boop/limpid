import 'package:limpid_design_system/golden.dart';

/// Les polices de l'application, par famille.
///
/// Les faces sont **embarquees par l'application** (D-13) : le design system
/// ne les declare pas, et son paquet n'a donc aucune police a lui seul.
const Map<String, List<String>> kGoldenFonts = <String, List<String>>{
  'Fraunces': <String>['Fraunces-Regular.ttf', 'Fraunces-Bold.ttf'],
  'Instrument Sans': <String>[
    'InstrumentSans-Regular.ttf',
    'InstrumentSans-Bold.ttf',
  ],
  'Literata': <String>['Literata-Regular.ttf', 'Literata-Bold.ttf'],
  'IBM Plex Mono': <String>['IBMPlexMono-Regular.ttf', 'IBMPlexMono-Bold.ttf'],
};

/// Le dossier des polices de l'application, vu depuis le paquet.
const String kGoldenFontsDirectory = '../../apps/limpid_app/assets/fonts';

/// Charge les polices reelles dans le test.
///
/// Le temoin structurel n'en depend pas — il ne mesure jamais le texte —
/// mais le temoin d'image, lui, montre la typographie reelle.
Future<void> loadGoldenFonts() async {
  await GoldenFonts.loadMaterialIcons();
  for (final MapEntry<String, List<String>> entry in kGoldenFonts.entries) {
    await GoldenFonts.loadFamily(
      entry.key,
      entry.value
          .map((String file) => '$kGoldenFontsDirectory/$file')
          .toList(growable: false),
    );
  }
}
