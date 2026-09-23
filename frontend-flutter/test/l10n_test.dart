import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The messages of an ARB file, without its `@` metadata.
Map<String, String> _messages(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

/// The words of [text] that address the player as "vous" (2026-09-23: the
/// French client says "tu" everywhere). Pronouns and possessives, and the
/// 2nd-person-plural verb forms: every word ending in "-ez" ("Choisissez",
/// "Réessayez", "Connectez-vous"), plus "êtes", "faites", "dites".
/// Word-boundary aware: "rendez-vous" and the few "-ez" words that are not
/// verbs ("chez", "nez", "assez") are not markers.
List<String> vousMarkers(String text) {
  final stripped = text.replaceAll(
    RegExp('rendez-vous', caseSensitive: false),
    '',
  );
  const notVerbs = {'chez', 'nez', 'assez', 'rez'};
  final word = RegExp(r'(?<![\p{L}])\p{L}+(?![\p{L}])', unicode: true);
  return [
    for (final m in word.allMatches(stripped))
      if (_isVousMarker(m[0]!.toLowerCase(), notVerbs)) m[0]!,
  ];
}

bool _isVousMarker(String w, Set<String> notVerbs) {
  if (const {'vous', 'votre', 'vos', 'êtes', 'faites', 'dites'}.contains(w)) {
    return true;
  }
  return w.endsWith('ez') && !notVerbs.contains(w);
}

void main() {
  test('every French message has an English translation and vice versa', () {
    final fr = _messages('lib/l10n/app_fr.arb').keys.toSet();
    final en = _messages('lib/l10n/app_en.arb').keys.toSet();
    expect(en.difference(fr), isEmpty, reason: 'keys only in app_en.arb');
    expect(fr.difference(en), isEmpty, reason: 'keys only in app_fr.arb');
  });

  group('the French client says "tu"', () {
    test('no message of app_fr.arb says "vous"', () {
      final offenders = {
        for (final e in _messages('lib/l10n/app_fr.arb').entries)
          if (vousMarkers(e.value).isNotEmpty) e.key: vousMarkers(e.value),
      };
      expect(
        offenders,
        isEmpty,
        reason: 'the French client speaks "tu" (FrontendFlutter.md)',
      );
    });

    test('the marker check finds "vous" and nothing else', () {
      expect(vousMarkers('Vous'), ['Vous']);
      expect(vousMarkers("Ce n'est pas votre tour."), ['votre']);
      expect(vousMarkers('Vos parties'), ['Vos']);
      expect(vousMarkers('Choisissez combien'), ['Choisissez']);
      expect(vousMarkers('Connectez-vous'), ['Connectez', 'vous']);
      expect(vousMarkers('Réessayez.'), ['Réessayez']);
      expect(vousMarkers('Vous êtes contré'), ['Vous', 'êtes']);
      expect(vousMarkers('Un rendez-vous chez toi, assez vite'), isEmpty);
      expect(vousMarkers('Choisis, à toi de jouer (toi)'), isEmpty);
      expect(vousMarkers('Tu es contré : ta main, {hand}'), isEmpty);
    });
  });
}
