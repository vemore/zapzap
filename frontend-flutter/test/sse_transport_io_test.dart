import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zapzap/services/sse_parser.dart';
import 'package:zapzap/services/sse_transport.dart';
import 'package:zapzap/services/sse_transport_io.dart';

final _uri = Uri.parse('http://localhost:9999/suscribeupdate?token=t');

/// A transport over a mock server whose body the test writes to.
({
  HttpSseTransport transport,
  StreamController<List<int>> body,
  List<http.BaseRequest> requests,
})
_server({int status = 200, Duration idle = const Duration(seconds: 60)}) {
  final body = StreamController<List<int>>();
  final requests = <http.BaseRequest>[];
  final transport = HttpSseTransport(
    idleTimeout: idle,
    clientFactory: () => MockClient.streaming((request, _) async {
      requests.add(request);
      return http.StreamedResponse(body.stream, status);
    }),
  );
  return (transport: transport, body: body, requests: requests);
}

void main() {
  group('HttpSseTransport', () {
    test(
      'asks for an event stream, opens, parses chunks as they come',
      () async {
        final server = _server();
        var opened = false;
        final messages = <SseMessage>[];
        final done = Completer<void>();
        server.transport
            .connect(_uri, onOpen: () => opened = true)
            .listen(messages.add, onDone: done.complete);

        server.body.add(
          utf8.encode('retry: 1000\nevent: connected\ndata: {}\n\n'),
        );
        server.body.add(utf8.encode('event: event\ndata: {"action":'));
        server.body.add(utf8.encode('"play","who":"Zoé"}\n\n'));
        await server.body.close();
        await done.future;

        expect(opened, isTrue);
        expect(server.requests.single.url, _uri);
        expect(server.requests.single.headers['Accept'], 'text/event-stream');
        expect(messages, [
          const SseMessage(event: 'connected', data: '{}'),
          const SseMessage(
            event: 'event',
            data: '{"action":"play","who":"Zoé"}',
          ),
        ]);
      },
    );

    test('a non-200 answer fails without opening', () async {
      final server = _server(status: 502);
      var opened = false;
      await expectLater(
        server.transport.connect(_uri, onOpen: () => opened = true),
        emitsError(isA<SseConnectionException>()),
      );
      expect(opened, isFalse);
    });

    test('a silent stream fails after the idle timeout', () async {
      final server = _server(idle: const Duration(milliseconds: 50));
      await expectLater(
        server.transport.connect(_uri),
        emitsInOrder([emitsError(isA<SseConnectionException>()), emitsDone]),
      );
    });
  });
}
