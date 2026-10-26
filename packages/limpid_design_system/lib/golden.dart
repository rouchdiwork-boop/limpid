/// The structural witness of the Limpid design system.
///
/// A golden image is **pixel for pixel**: an image generated on Windows does
/// not match on Linux, because the text rendering and the antialiasing
/// differ. Such an image cannot be a contract of the continuous integration.
///
/// The witness of this library is therefore **structural**: it describes the
/// rendered tree — the widgets, their texts, their resolved colors, their
/// radii, their spacings — and compares that description with a stored
/// expectation. The same description is produced on every platform, so the
/// expectation is a real contract, and it is readable: a failure says which
/// widget changed and which value.
///
/// ```dart
/// final GoldenDescription description = GoldenExtractor.describe(element);
/// final GoldenWitness witness = GoldenWitnessTool.check(
///   file: File('test/expectations/limpid_badge.txt'),
///   title: 'LimpidBadge',
///   section: 'paper',
///   order: <String>['paper', 'sepia', 'night', 'contrast'],
///   actual: description.toLines(),
///   isUpdating: autoUpdateGoldenFiles,
/// );
/// expect(witness.isMatching, isTrue, reason: witness.report);
/// ```
library;

export 'package:limpid_design_system/src/golden/golden_diff.dart';
export 'package:limpid_design_system/src/golden/golden_expectation.dart';
export 'package:limpid_design_system/src/golden/golden_extractor.dart';
export 'package:limpid_design_system/src/golden/golden_fonts.dart';
export 'package:limpid_design_system/src/golden/golden_node.dart';
export 'package:limpid_design_system/src/golden/golden_witness.dart';
