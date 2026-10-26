import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The keys of the publication, in French and in English.
///
/// The action of publication introduced them: the interface must never show
/// a hardcoded string, and the two locales must always carry the same keys.
const List<String> _publicationKeys = <String>[
  'projectPublishAction',
  'projectUnpublishAction',
  'projectPublishConfirmTitle',
  'projectPublishConfirmMessage',
  'projectPublishConfirmAction',
  'projectUnpublishConfirmTitle',
  'projectUnpublishConfirmMessage',
  'projectUnpublishConfirmAction',
  'projectPublicationStateDraft',
  'projectPublicationStatePublished',
  'projectPublicationStateShowcase',
  'projectPublicationFailed',
];

void main() {
  /// Reads the keys of an ARB file.
  Set<String> keysOf(String path) {
    final String content = File(path).readAsStringSync();
    final Object? decoded = jsonDecode(content);
    if (decoded is! Map<String, Object?>) {
      throw StateError('The ARB file $path is not a JSON object.');
    }
    return decoded.keys.where((String key) => !key.startsWith('@')).toSet();
  }

  test('the two ARB files carry the same keys', () {
    final Set<String> french = keysOf('lib/l10n/app_fr.arb');
    final Set<String> english = keysOf('lib/l10n/app_en.arb');

    expect(english.difference(french), isEmpty);
    expect(french.difference(english), isEmpty);
  });

  test('the keys of the publication are in the two ARB files', () {
    final Set<String> french = keysOf('lib/l10n/app_fr.arb');
    final Set<String> english = keysOf('lib/l10n/app_en.arb');

    for (final String key in _publicationKeys) {
      expect(french, contains(key), reason: '$key is missing in French');
      expect(english, contains(key), reason: '$key is missing in English');
    }
  });
}
