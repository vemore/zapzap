import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zapzap/utils/date_format.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr');
    await initializeDateFormatting('en');
  });

  group('dateTime', () {
    // 2026-09-22 20:26:48 UTC, the fixtures' `finishedAt` (Unix seconds).
    final finishedAt = DateTime.utc(2026, 9, 22, 20, 26, 48);

    test('shows the date and the time in the locale, in the device zone', () {
      final local = finishedAt.toLocal();
      final day = local.day.toString().padLeft(2, '0');
      final month = local.month.toString().padLeft(2, '0');
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      expect(
        Formats.dateTime(finishedAt, 'fr'),
        '$day/$month/${local.year} $hour:$minute',
      );
      // English puts the month first and pads nothing, which is the point of
      // formatting in the locale rather than with a fixed pattern.
      expect(
        Formats.dateTime(finishedAt, 'en'),
        startsWith('${local.month}/${local.day}/'),
      );
    });

    test('the clock is the locale\'s: 24-hour in French, 12-hour in '
        'English', () {
      final afternoon = DateTime(2026, 9, 22, 14, 26).toUtc();
      expect(Formats.dateTime(afternoon, 'fr'), endsWith('14:26'));
      expect(Formats.dateTime(afternoon, 'en'), endsWith('2:26\u202fPM'));
    });

    test('a missing date is a dash', () {
      expect(Formats.dateTime(null, 'fr'), Formats.missing);
    });
  });

  group('percent', () {
    test('a 0..1 rate becomes a percentage with one decimal', () {
      expect(Formats.percent(0), '0.0%');
      expect(Formats.percent(1), '100.0%');
      expect(Formats.percent(0.6), '60.0%');
      expect(Formats.percent(0.3333), '33.3%');
    });

    test('a missing rate is zero, as React reads an absent field', () {
      expect(Formats.percent(null), '0.0%');
    });
  });

  test('number drops a decimal that is zero', () {
    expect(Formats.number(134), '134');
    expect(Formats.number(134.0), '134');
    expect(Formats.number(12.5), '12.5');
    expect(Formats.number(12.96), '13');
    expect(Formats.number(12.04), '12');
    expect(Formats.number(null), '0');
  });

  test('decimal keeps one digit', () {
    expect(Formats.decimal(122), '122.0');
    expect(Formats.decimal(null), '0.0');
  });
}
