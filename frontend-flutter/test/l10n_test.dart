import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The message keys of an ARB file, without its `@` metadata.
Set<String> _keys(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return json.keys.where((k) => !k.startsWith('@')).toSet();
}

void main() {
  test('every French message has an English translation and vice versa', () {
    final fr = _keys('lib/l10n/app_fr.arb');
    final en = _keys('lib/l10n/app_en.arb');
    expect(en.difference(fr), isEmpty, reason: 'keys only in app_en.arb');
    expect(fr.difference(en), isEmpty, reason: 'keys only in app_fr.arb');
  });
}
