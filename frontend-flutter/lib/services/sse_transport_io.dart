import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sse_parser.dart';
import 'sse_transport.dart';

SseTransport createSseTransport() => HttpSseTransport();

/// Server-sent events over a streamed `package:http` response, the
/// transport on Android: the body is decoded as UTF-8 and fed to
/// [SseParser].
///
/// Each connection has its own `http.Client`, closed with it, which aborts
/// the response. A stream silent for [idleTimeout] counts as lost: both
/// backends send a heartbeat comment every 20 s, so a half-open socket
/// (a phone changing network) is noticed rather than waited on forever.
class HttpSseTransport implements SseTransport {
  HttpSseTransport({
    http.Client Function()? clientFactory,
    this.idleTimeout = defaultIdleTimeout,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  static const Duration defaultIdleTimeout = Duration(seconds: 60);

  final http.Client Function() _clientFactory;
  final Duration idleTimeout;

  @override
  Stream<SseMessage> connect(Uri uri, {void Function()? onOpen}) {
    final client = _clientFactory();
    StreamSubscription<String>? body;
    var closed = false;
    late final StreamController<SseMessage> controller;

    void finish([Object? error, StackTrace? stack]) {
      if (closed) return;
      closed = true;
      body?.cancel();
      client.close();
      if (error != null) controller.addError(error, stack);
      controller.close();
    }

    Future<void> open() async {
      try {
        final request = http.Request('GET', uri)
          ..headers['Accept'] = 'text/event-stream'
          ..headers['Cache-Control'] = 'no-cache';
        final response = await client.send(request);
        if (closed) return;
        if (response.statusCode != 200) {
          finish(SseConnectionException('HTTP ${response.statusCode}'));
          return;
        }
        onOpen?.call();
        final parser = SseParser();
        body = response.stream
            .transform(utf8.decoder)
            .timeout(idleTimeout)
            .listen(
              (chunk) {
                for (final message in parser.add(chunk)) {
                  controller.add(message);
                }
              },
              onError: (Object error, StackTrace stack) => finish(
                error is TimeoutException
                    ? const SseConnectionException('idle stream')
                    : error,
                stack,
              ),
              onDone: finish,
            );
      } catch (error, stack) {
        finish(error, stack);
      }
    }

    controller = StreamController<SseMessage>(
      onListen: open,
      onCancel: () {
        closed = true;
        body?.cancel();
        client.close();
      },
    );
    return controller.stream;
  }
}
