import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/l10n/app_localizations.dart';

/// The `=0` plural cases added to `gameSuggestSequence`, `gameTableTakeHint`
/// and `gameZapZapSheetTitle` in es, pt, de, ru, hi and id
/// (wip/todo/2026-09-27-flutter-l10n-plural-zero-cases.md): a count of 0
/// must not fall into the CLDR `one` category (pt and hi, where `one`
/// includes 0) and must not mention a joker that is not there.
void main() {
  final locales = {
    for (final code in ['es', 'pt', 'de', 'ru', 'hi', 'id'])
      code: lookupAppLocalizations(Locale(code)),
  };

  group('gameSuggestSequence with 0 jokers renders the run without a joker '
      'mention', () {
    const expected = {
      'es': 'Escalera 3–5♥',
      'pt': 'Sequência 3–5♥',
      'de': 'Reihe 3–5♥',
      'ru': 'Последовательность 3–5♥',
      'hi': 'सीक्वेंस 3–5♥',
      'id': 'Urutan 3–5♥',
    };
    for (final code in expected.keys) {
      test(code, () {
        expect(
          locales[code]!.gameSuggestSequence(0, '3', '5', '♥'),
          expected[code],
        );
      });
    }
  });

  group('gameTableTakeHint with 0 points adds no point', () {
    const expected = {
      'es': 'Tomar 7♥ no suma puntos a tu mano.',
      'pt': 'Pegar 7♥ não adiciona pontos à sua mão.',
      'de': 'Mit 7♥ kommt kein Punkt zu deiner Hand hinzu.',
      'ru': '7♥ не добавит очков к руке.',
      'hi': '7♥ लेने से आपके हाथ में कोई अंक नहीं जुड़ता।',
      'id': 'Mengambil 7♥ tidak menambah poin ke tanganmu.',
    };
    for (final code in expected.keys) {
      test(code, () {
        expect(locales[code]!.gameTableTakeHint(0, '7♥'), expected[code]);
      });
    }
  });

  group('gameZapZapSheetTitle with 0 points does not read a singular unit '
      '(pt: not "0 ponto")', () {
    const expected = {
      'es': '¿Cantar ZapZap con 0 puntos?',
      'pt': 'Anunciar ZapZap com 0 pontos?',
      'de': 'ZapZap mit 0 Punkten rufen?',
      'ru': 'Объявить ZapZap с 0 очков?',
      'hi': '0 अंक पर ZapZap बोलें?',
      'id': 'Serukan ZapZap dengan 0 poin?',
    };
    for (final code in expected.keys) {
      test(code, () {
        expect(locales[code]!.gameZapZapSheetTitle(0), expected[code]);
      });
    }
    test('pt never reads the singular "ponto" at 0', () {
      expect(
        locales['pt']!.gameZapZapSheetTitle(0),
        isNot(contains('0 ponto?')),
      );
    });
  });
}
