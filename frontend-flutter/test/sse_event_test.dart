import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/models/sse_event.dart';
import 'package:zapzap/services/sse_parser.dart';

SseEvent? _parse(String data, {String event = 'event'}) =>
    SseEvent.fromMessage(SseMessage(event: event, data: data));

void main() {
  group('SseEvent', () {
    // `GameEvent` (zapzap-rust/src/infrastructure/app_state.rs) as the
    // selectHandSize route sends it: `data` flattened into the object.
    test('a game broadcast', () {
      final event = _parse(
        '{"type":"gameUpdate","partyId":"p1","userId":"u1",'
        '"action":"selectHandSize","handSize":5,"timestamp":1726999999999}',
      )!;
      expect(event.type, 'gameUpdate');
      expect(event.partyId, 'p1');
      expect(event.userId, 'u1');
      expect(event.action, 'selectHandSize');
      expect(event.isPresence, isFalse);
      expect(event.data['handSize'], 5);
    });

    test('a broadcast carries a millisecond timestamp', () {
      final event = _parse(
        '{"type":"gameUpdate","partyId":"p1","userId":"u1",'
        '"action":"play","timestamp":1726999999999}',
      )!;
      expect(event.type, 'gameUpdate');
      expect(event.action, 'play');
      expect(event.timestamp, DateTime.utc(2024, 9, 22, 10, 13, 19, 999));
    });

    test('presence events: no party, a username (api/sse.rs)', () {
      for (final type in ['userConnected', 'userDisconnected']) {
        final event = _parse(
          '{"type":"$type","partyId":null,"userId":"u1",'
          '"username":"Ana","timestamp":1726999999999}',
        )!;
        expect(event.isPresence, isTrue);
        expect(event.partyId, isNull);
        expect(event.userId, 'u1');
      }
    });

    test('only the named event `event` is a broadcast', () {
      expect(_parse('{"partyId":"p1"}', event: 'message'), isNull);
    });

    test('the initial connected event and unreadable data are skipped', () {
      expect(
        _parse(
          '{"message":"Connected to SSE stream","timestamp":1726999999999}',
          event: 'connected',
        ),
        isNull,
      );
      expect(_parse('not json'), isNull);
      expect(_parse('[1,2]'), isNull);
    });
  });
}
