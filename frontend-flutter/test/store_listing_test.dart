import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'l10n_test.dart' show vousMarkers;

/// The Google Play store listing, `store_listing/` at the repository root
/// (store_listing/README.md): what Play refuses on upload, checked here so a
/// text or an image that breaks a limit fails CI rather than the publication.
const _listing = '../store_listing';
const _locales = ['fr-FR', 'en-US'];

/// Play's limits, in characters (Unicode code points, not UTF-16 units).
const _textLimits = {
  'title.txt': 30,
  'short_description.txt': 80,
  'full_description.txt': 4000,
};

/// The width, height and colour type of a PNG, read from its IHDR chunk.
({int width, int height, int colorType}) _png(String path) {
  final bytes = File(path).readAsBytesSync();
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  expect(bytes.sublist(0, 8), signature, reason: '$path is not a PNG');
  expect(String.fromCharCodes(bytes.sublist(12, 16)), 'IHDR');
  final data = ByteData.sublistView(bytes);
  return (
    width: data.getUint32(16),
    height: data.getUint32(20),
    colorType: bytes[25],
  );
}

// PNG colour types: 2 truecolour (RGB), 6 truecolour with alpha (RGBA).
const _rgb = 2;
const _rgba = 6;

void main() {
  for (final locale in _locales) {
    group(locale, () {
      for (final entry in _textLimits.entries) {
        test('${entry.key} is not empty and within ${entry.value} '
            'characters', () {
          final text = File('$_listing/$locale/${entry.key}')
              .readAsStringSync();
          expect(text.trim(), isNotEmpty);
          expect(
            text.runes.length,
            lessThanOrEqualTo(entry.value),
            reason: '$locale/${entry.key}: ${text.runes.length} characters',
          );
          expect(
            text,
            isNot(endsWith('\n')),
            reason: 'the newline would be uploaded too',
          );
        });
      }

      test('the title and short description are one line', () {
        for (final name in ['title.txt', 'short_description.txt']) {
          final text = File('$_listing/$locale/$name').readAsStringSync();
          expect(text, isNot(contains('\n')), reason: '$locale/$name');
        }
      });

      test('the full description is plain text (no HTML, no Markdown)', () {
        final text = File('$_listing/$locale/full_description.txt')
            .readAsStringSync();
        expect(text, isNot(contains(RegExp(r'<[a-zA-Z/]'))));
        expect(
          text,
          isNot(contains(RegExp(r'^\s*(#|\*|- )', multiLine: true))),
        );
        expect(text, isNot(contains('**')));
      });

      test('2 to 8 phone screenshots, 9:16, each side 320 to 3840 px, '
          'opaque', () {
        final shots = Directory('$_listing/$locale/screenshots/phone')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.png'))
            .toList();
        expect(shots.length, inInclusiveRange(2, 8));
        for (final shot in shots) {
          final png = _png(shot.path);
          expect(png.width, inInclusiveRange(320, 3840), reason: shot.path);
          expect(png.height, inInclusiveRange(320, 3840), reason: shot.path);
          expect(png.width * 16, png.height * 9, reason: '${shot.path} 9:16');
          expect(png.colorType, _rgb, reason: '${shot.path}: no alpha');
        }
      });
    });
  }

  test('the French listing says "tu", as the app does', () {
    for (final name in _textLimits.keys) {
      final text = File('$_listing/fr-FR/$name').readAsStringSync();
      expect(vousMarkers(text), isEmpty, reason: 'fr-FR/$name');
    }
  });

  test('the icon is 512x512, 32-bit (RGBA)', () {
    final png = _png('$_listing/assets/icon_512.png');
    expect((png.width, png.height), (512, 512));
    expect(png.colorType, _rgba);
  });

  test('the feature graphic is 1024x500, with no alpha', () {
    final png = _png('$_listing/assets/feature_graphic.png');
    expect((png.width, png.height), (1024, 500));
    expect(png.colorType, _rgb);
  });
}
