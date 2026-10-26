import 'dart:typed_data';

import 'package:limpid_export/limpid_export.dart';
import 'package:test/test.dart';

void main() {
  group('FontRegistry', () {
    test('sans chargeur, aucune police n est disponible', () async {
      final registry = FontRegistry();
      final resolved = await registry.resolve('Literata');
      expect(resolved.isFallback, isTrue);
      expect(resolved.requestedFamily, 'Literata');
    });

    test('charge les assets et les met en cache', () async {
      final calls = <String>[];
      final registry = FontRegistry(
        loader: (path) async {
          calls.add(path);
          return Uint8List.fromList(<int>[1, 2, 3]);
        },
      );
      final resolved = await registry.resolve('Literata');
      expect(resolved.isFallback, isFalse);
      expect(resolved.effectiveFamily, 'Literata');
      expect(resolved.regular, isNotNull);
      expect(calls, contains('assets/fonts/Literata-Regular.ttf'));

      final before = calls.length;
      await registry.resolve('Literata');
      expect(calls.length, before, reason: 'Les assets doivent etre caches.');
    });

    test('un asset illisible ne leve pas d exception', () async {
      final registry = FontRegistry(
        loader: (path) async => throw StateError('asset corrompu'),
      );
      final resolved = await registry.resolve('Literata');
      expect(resolved.isFallback, isTrue);
    });

    test('le catalogue liste les faces du projet', () {
      expect(LimpidFonts.families, contains('Literata'));
      expect(LimpidFonts.families, contains('Fraunces'));
      expect(LimpidFonts.families, contains('Instrument Sans'));
      expect(LimpidFonts.families, contains('IBM Plex Mono'));
      final asset = LimpidFonts.assetFor('Fraunces', FontVariant.bold);
      expect(asset.assetPath, 'assets/fonts/Fraunces-Bold.ttf');
    });
  });
}
