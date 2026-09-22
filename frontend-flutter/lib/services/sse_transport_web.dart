import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'sse_parser.dart';
import 'sse_transport.dart';

SseTransport createSseTransport() => EventSourceSseTransport();

/// Server-sent events over the browser's `EventSource`, the transport of
/// the PWA.
///
/// Listens to the backends' named `event` events and to unnamed `message`
/// ones. On an error the source is closed rather than left to the
/// browser's own reconnection, so `SseClient` alone decides when to retry,
/// as the React `useSSE` does.
class EventSourceSseTransport implements SseTransport {
  @override
  Stream<SseMessage> connect(Uri uri, {void Function()? onOpen}) {
    web.EventSource? source;
    late final StreamController<SseMessage> controller;

    void forward(web.MessageEvent event) {
      controller.add(
        SseMessage(
          event: event.type,
          data: event.data.dartify()?.toString() ?? '',
          id: event.lastEventId.isEmpty ? null : event.lastEventId,
        ),
      );
    }

    controller = StreamController<SseMessage>(
      onListen: () {
        final opened = web.EventSource(uri.toString());
        source = opened;
        opened.onopen = ((web.Event _) => onOpen?.call()).toJS;
        opened.addEventListener('event', forward.toJS);
        opened.addEventListener('message', forward.toJS);
        opened.onerror = ((web.Event _) {
          opened.close();
          controller.addError(
            const SseConnectionException('EventSource error'),
          );
          controller.close();
        }).toJS;
      },
      onCancel: () => source?.close(),
    );
    return controller.stream;
  }
}
