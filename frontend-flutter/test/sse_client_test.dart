import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/models/sse_event.dart';
import 'package:zapzap/providers/sse_provider.dart';
import 'package:zapzap/services/sse_client.dart';

import 'sse_fakes.dart';

final _uri = Uri.parse('http://localhost:9999/suscribeupdate');

void main() {
  group('SseClient', () {
    test('connects once with ?token= and forwards broadcasts only', () {
      fakeAsync((async) {
        final transport = FakeSseTransport();
        final client = SseClient(uri: _uri, transport: transport);
        final events = <SseEvent>[];
        client.events.listen(events.add);

        client.connect('jwt-1');
        expect(transport.connections, hasLength(1));
        expect(
          transport.last.uri.toString(),
          'http://localhost:9999/suscribeupdate?token=jwt-1',
        );
        expect(client.connected, isFalse);

        transport.last.open();
        expect(client.connected, isTrue);
        transport.last.send('{"type":"connected"}', event: 'connected');
        transport.last.send('{"partyId":"p1","action":"play"}');
        async.flushMicrotasks();

        expect(events.map((e) => e.action), ['play']);
        client.connect('jwt-1');
        expect(transport.connections, hasLength(1), reason: 'same token');
      });
    });

    test('reconnects 3 s after an error, not before', () {
      fakeAsync((async) {
        final transport = FakeSseTransport();
        final client = SseClient(uri: _uri, transport: transport);
        client.connect('jwt-1');
        transport.last.open();

        transport.last.fail();
        async.flushMicrotasks();
        expect(client.connected, isFalse);

        async.elapse(const Duration(milliseconds: 2999));
        expect(transport.connections, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(transport.connections, hasLength(2));
        expect(transport.last.uri.queryParameters['token'], 'jwt-1');

        transport.last.open();
        expect(client.connected, isTrue);
      });
    });

    test('reconnects 3 s after the server ends the stream, repeatedly', () {
      fakeAsync((async) {
        final transport = FakeSseTransport();
        final client = SseClient(uri: _uri, transport: transport);
        client.connect('jwt-1');
        for (var attempt = 1; attempt <= 3; attempt++) {
          transport.last.end();
          async.flushMicrotasks();
          async.elapse(SseClient.defaultReconnectDelay);
          expect(transport.connections, hasLength(attempt + 1));
        }
      });
    });

    test('disconnect closes the stream and cancels a pending retry', () {
      fakeAsync((async) {
        final transport = FakeSseTransport();
        final client = SseClient(uri: _uri, transport: transport);
        client.connect('jwt-1');
        transport.last.open();
        client.disconnect();
        expect(transport.last.cancelled, isTrue);
        expect(client.connected, isFalse);
        expect(client.token, isNull);

        client.connect('jwt-1');
        transport.last.fail();
        async.flushMicrotasks();
        client.disconnect();
        async.elapse(const Duration(seconds: 10));
        expect(transport.connections, hasLength(2));
      });
    });

    test('a new token replaces the connection; the old one is ignored', () {
      fakeAsync((async) {
        final transport = FakeSseTransport();
        final client = SseClient(uri: _uri, transport: transport);
        final events = <SseEvent>[];
        client.events.listen(events.add);
        client.connect('jwt-1');
        final first = transport.last;

        client.connect('jwt-2');
        expect(first.cancelled, isTrue);
        expect(transport.last.uri.queryParameters['token'], 'jwt-2');
        first.open();
        expect(client.connected, isFalse, reason: 'stale open');

        transport.last.send('{"partyId":"p2"}');
        async.flushMicrotasks();
        expect(events.single.partyId, 'p2');
      });
    });
  });

  group('SseProvider', () {
    test('notifies when connected changes and exposes the events', () {
      fakeAsync((async) {
        final transport = FakeSseTransport();
        final sse = SseProvider(uri: _uri, transport: transport);
        final states = <bool>[];
        sse.addListener(() => states.add(sse.connected));
        final events = <SseEvent>[];
        sse.events.listen(events.add);

        sse.connect('jwt-1');
        transport.last.open();
        transport.last.send('{"type":"userConnected","userId":"u1"}');
        transport.last.fail();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        transport.last.open();
        sse.disconnect();

        expect(states, [true, false, true, false]);
        expect(events.single.isPresence, isTrue);
        sse.dispose();
      });
    });
  });
}
