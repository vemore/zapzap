import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/services/token_storage.dart';
import 'package:zapzap/widgets/game_hand.dart';
import 'package:zapzap/widgets/game_hand_size_selector.dart';
import 'package:zapzap/widgets/game_player_table.dart';
import 'package:zapzap/widgets/game_table_area.dart';

import 'auth_helpers.dart';
import 'game_helpers.dart';
import 'sse_fakes.dart';

/// The languages translated from `app_en.arb` + `app_fr.arb` (2026-09-26):
/// the most used on the Play Store, ten with French and English.
const translated = ['es', 'pt', 'de', 'ru', 'ja', 'hi', 'id', 'ar'];

/// The plural categories CLDR gives each language: every `plural` of its ARB
/// file uses them all and no other, except that an explicit `=0`, `=1` or
/// `=2` stands for `zero`, `one` or `two` where [exactCategories] says that
/// category is that one number.
const pluralCategories = {
  'es': {'one', 'other'},
  'pt': {'one', 'other'},
  'de': {'one', 'other'},
  'ru': {'one', 'few', 'many', 'other'},
  'ja': {'other'},
  'hi': {'one', 'other'},
  'id': {'other'},
  'ar': {'zero', 'one', 'two', 'few', 'many', 'other'},
};

/// Per language, the categories an explicit case can stand for: `one` is 1
/// alone in German or Spanish (and 0 or 1 in Portuguese and Hindi, where 0
/// reads fine in `other`), but also 21, 31… in Russian, so there `=1` is not
/// enough.
const exactCategories = {
  'es': {'=1': 'one'},
  'pt': {'=1': 'one'},
  'de': {'=1': 'one'},
  'ru': <String, String>{},
  'ja': <String, String>{},
  'hi': {'=1': 'one'},
  'id': <String, String>{},
  'ar': {'=0': 'zero', '=1': 'one', '=2': 'two'},
};

/// The messages of an ARB file, without its `@` metadata.
Map<String, String> _messages(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

/// One argument of an ICU message: its name, its kind (`plural`, `select`
/// or null for a plain `{name}`), and the case keys of a plural or select.
typedef IcuArgument = ({String name, String? kind, Set<String> cases});

/// The arguments of an ICU [message], nested ones included. Throws a
/// [FormatException] on unbalanced braces or a malformed argument.
List<IcuArgument> icuArguments(String message) {
  final out = <IcuArgument>[];
  var i = 0;

  void skipSpaces() {
    while (i < message.length && message[i].trim().isEmpty) {
      i++;
    }
  }

  String word() {
    final start = i;
    while (i < message.length && RegExp(r'[\w=]').hasMatch(message[i])) {
      i++;
    }
    return message.substring(start, i);
  }

  void expectChar(String c) {
    if (i >= message.length || message[i] != c) {
      throw FormatException('expected "$c"', message, i);
    }
    i++;
  }

  // Declared ahead: text and argument call each other.
  late final void Function() argument;

  // Parses text up to a closing brace (nested) or the end (top level).
  void text({required bool nested}) {
    while (i < message.length) {
      final c = message[i];
      if (c == '}') {
        if (nested) return;
        throw FormatException('unbalanced "}"', message, i);
      }
      if (c == '{') {
        i++;
        argument();
      } else {
        i++;
      }
    }
    if (nested) throw FormatException('unclosed "{"', message, i);
  }

  // After an opening brace: `name}` or `name, plural|select, cases}`.
  argument = () {
    skipSpaces();
    final name = word();
    if (name.isEmpty) throw FormatException('empty argument', message, i);
    skipSpaces();
    if (i < message.length && message[i] == '}') {
      i++;
      out.add((name: name, kind: null, cases: const {}));
      return;
    }
    expectChar(',');
    skipSpaces();
    final kind = word();
    if (kind != 'plural' && kind != 'select') {
      throw FormatException('unknown argument kind "$kind"', message, i);
    }
    skipSpaces();
    expectChar(',');
    final cases = <String>{};
    while (true) {
      skipSpaces();
      if (i < message.length && message[i] == '}') {
        i++;
        break;
      }
      final key = word();
      if (key.isEmpty) throw FormatException('empty case', message, i);
      cases.add(key);
      skipSpaces();
      expectChar('{');
      text(nested: true);
      expectChar('}');
    }
    out.add((name: name, kind: kind, cases: cases));
  };

  text(nested: false);
  return out;
}

void main() {
  final fr = _messages('lib/l10n/app_fr.arb');
  final en = _messages('lib/l10n/app_en.arb');

  test('the ICU parser finds arguments, plurals and their cases', () {
    expect(icuArguments('Salut'), isEmpty);
    expect(
      icuArguments(
        '{player} a posé {count, plural, =1{1 carte} '
        'other{{count} cartes}}',
      ).map((a) => '${a.name} ${a.kind} ${a.cases.join(',')}'),
      ['player null ', 'count null ', 'count plural =1,other'],
    );
    expect(() => icuArguments('{count, plural, one{x}'), throwsFormatException);
    expect(() => icuArguments('a } b'), throwsFormatException);
  });

  for (final code in translated) {
    group('app_$code.arb', () {
      final path = 'lib/l10n/app_$code.arb';
      final json =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      final messages = _messages(path);

      test(
        'declares its locale and carries exactly the keys of app_fr.arb',
        () {
          expect(json['@@locale'], code);
          expect(
            messages.keys.toSet().difference(fr.keys.toSet()),
            isEmpty,
            reason: 'keys only in app_$code.arb',
          );
          expect(
            fr.keys.toSet().difference(messages.keys.toSet()),
            isEmpty,
            reason: 'keys missing from app_$code.arb',
          );
        },
      );

      test('every message keeps the placeholders of the English one', () {
        final wrong = <String, String>{};
        for (final key in fr.keys) {
          final want = {for (final a in icuArguments(en[key]!)) a.name};
          final got = {for (final a in icuArguments(messages[key]!)) a.name};
          if (!setEquals(want, got)) wrong[key] = '$got, want $want';
        }
        expect(wrong, isEmpty);
      });

      test('every plural uses the CLDR categories of the language, never '
          'an explicit case and its category together, and every plural '
          'and select has an "other" case', () {
        final allowed = pluralCategories[code]!;
        final wrong = <String, String>{};
        for (final e in messages.entries) {
          for (final a in icuArguments(e.value)) {
            if (a.kind == null) continue;
            if (!a.cases.contains('other')) {
              wrong[e.key] = '${a.name}: no other';
            }
            if (a.kind != 'plural') continue;
            final categories = a.cases.where((c) => !c.startsWith('='));
            // gen-l10n takes `=1` and `one` for the same case, and keeps
            // the later one: a message with both says one of them for
            // nothing.
            for (final (exact, category) in const [
              ('=0', 'zero'),
              ('=1', 'one'),
              ('=2', 'two'),
            ]) {
              if (a.cases.contains(exact) && a.cases.contains(category)) {
                wrong[e.key] = '${a.name}: both $exact and $category';
              }
            }
            final covered = {
              ...categories,
              for (final c in a.cases) ?exactCategories[code]![c],
            };
            if (!covered.containsAll(allowed) ||
                !allowed.containsAll(categories)) {
              wrong[e.key] = '${a.name}: $categories, want $allowed';
            }
          }
        }
        expect(wrong, isEmpty);
      });
    });
  }

  group('resolveLocale', () {
    final supported = AppLocalizations.supportedLocales;

    test('the ten languages are supported', () {
      expect(supported.map((l) => l.languageCode).toSet(), {
        'fr',
        'en',
        ...translated,
      });
    });

    test('picks the device language, whatever its region', () {
      for (final device in const [
        Locale('es', 'MX'),
        Locale('pt', 'BR'),
        Locale('pt', 'PT'),
        Locale('de', 'AT'),
        Locale('ru'),
        Locale('ja', 'JP'),
        Locale('hi', 'IN'),
        Locale('id', 'ID'),
        Locale('ar', 'EG'),
        Locale('en', 'US'),
        Locale('fr', 'CA'),
      ]) {
        expect(
          resolveLocale(device, supported).languageCode,
          device.languageCode,
        );
      }
    });

    test('falls back to French for another language, or none', () {
      expect(
        resolveLocale(const Locale('zh', 'CN'), supported),
        const Locale('fr'),
      );
      expect(resolveLocale(null, supported), const Locale('fr'));
    });
  });

  for (final code in translated) {
    testWidgets('the home screen speaks $code', (tester) async {
      await tester.pumpWidget(
        ZapZapApp(
          apiConfig: testConfig,
          locale: Locale(code),
          tokenStorage: MemoryTokenStorage(),
        ),
      );
      await tester.pumpAndSettle();

      final strings = lookupAppLocalizations(Locale(code));
      expect(strings.homeTagline, isNot(fr['homeTagline']));
      expect(strings.homeTagline, isNot(en['homeTagline']));
      expect(find.text(strings.homeTagline), findsOneWidget);
      expect(find.text(strings.homeLoginButton), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(strings.homeTagline))),
        code == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // The translated strings are longer than the French ones in some
  // languages, and Arabic mirrors the board: each phase of the game on a
  // phone, in each language, at the default and a large text scale.
  group('the board on a 360×740 phone', () {
    Future<void> pumpGame(
      WidgetTester tester,
      String code,
      FakeGameBackend backend,
      double textScale,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ZapZapApp(
          apiConfig: testConfig,
          locale: Locale(code),
          initialLocation: AppRoutes.gamePath('p1'),
          apiClient: backend.client(),
          tokenStorage: storedSession(validToken),
          sseTransport: FakeSseTransport(),
        ),
      );
      await tester.pumpAndSettle();
    }

    FakeGameBackend phase(String action) => FakeGameBackend(
      state: gameSnapshotJson(
        gameState: gameStateJson(
          currentTurn: 0,
          currentAction: action,
          playerHand: action == 'selectHandSize'
              ? const []
              : const [0, 1, 2, 3, 4, 5, 6],
          lastCardsPlayed: action == 'selectHandSize'
              ? const []
              : const [30, 31, 32],
          isGoldenScore: action == 'selectHandSize',
        ),
      ),
    );

    for (final code in translated) {
      for (final scale in [1.0, 1.5]) {
        for (final action in ['play', 'draw', 'selectHandSize']) {
          testWidgets('$code, $action, text scale $scale', (tester) async {
            await pumpGame(tester, code, phase(action), scale);

            expect(find.byType(GamePlayerTable), findsOneWidget);
            if (action == 'selectHandSize') {
              expect(find.byType(GameHandSizeSelector), findsOneWidget);
            } else {
              expect(find.byType(GameTableArea), findsOneWidget);
              expect(find.byType(GameHand), findsOneWidget);
            }
            expect(
              Directionality.of(tester.element(find.byType(GamePlayerTable))),
              code == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
