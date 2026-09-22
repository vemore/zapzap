import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/models/sse_event.dart';
import 'package:zapzap/services/sse_parser.dart';

SseEvent? _parse(String data, {String event = 'event'}) =>
    SseEvent.fromMessage(SseMessage(event: event, data: data));

void main() {
  group('SseEvent', () {
    test('a Node game broadcast', () {
      final event = _parse(
        '{"partyId":"p1","userId":3,"action":"selectHandSize","handSize":5}',
      )!;
      expect(event.partyId, 'p1');
      expect(event.userId, '3');
      expect(event.action, 'selectHandSize');
      expect(event.type, isNull);
      expect(event.isPresence, isFalse);
      expect(event.data['handSize'], 5);
    });

    test('a Rust broadcast carries a type and a millisecond timestamp', () {
      final event = _parse(
        '{"type":"gameUpdate","partyId":"p1","userId":"u1",'
        '"action":"play","timestamp":1726999999999}',
      )!;
      expect(event.type, 'gameUpdate');
      expect(event.action, 'play');
      expect(event.timestamp, DateTime.utc(2024, 9, 22, 10, 13, 19, 999));
    });

    test('presence events', () {
      for (final type in [
        'userConnected',
        'userDisconnected',
        'userStatusChanged',
      ]) {
        expect(_parse('{"type":"$type","userId":"u1"}')!.isPresence, isTrue);
      }
    });

    test('an unnamed message is read too', () {
      expect(_parse('{"partyId":"p1"}', event: 'message')!.partyId, 'p1');
    });

    test('the initial connected event and unreadable data are skipped', () {
      expect(_parse('{"type":"connected"}', event: 'connected'), isNull);
      expect(_parse('not json'), isNull);
      expect(_parse('[1,2]'), isNull);
    });
  });
}
