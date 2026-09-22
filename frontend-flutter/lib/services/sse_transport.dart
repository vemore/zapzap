import 'sse_parser.dart';
import 'sse_transport_io.dart'
    if (dart.library.js_interop) 'sse_transport_web.dart'
    as platform;

/// How one server-sent events connection is opened: over a streamed HTTP
/// response on Android (`HttpSseTransport`), over the browser's
/// `EventSource` on the web (`EventSourceSseTransport`).
///
/// A transport never reconnects: `SseClient` does, on its own delay.
abstract interface class SseTransport {
  /// Opens [uri]. [onOpen] fires once the server has accepted the stream;
  /// the returned stream then carries every event and ends, or fails, when
  /// the connection is lost. Cancelling the subscription closes the
  /// connection.
  Stream<SseMessage> connect(Uri uri, {void Function()? onOpen});
}

/// The transport of the platform the app runs on.
SseTransport createPlatformTransport() => platform.createSseTransport();

/// The connection failed or dropped (a non-200 answer, an idle stream, an
/// `EventSource` error).
class SseConnectionException implements Exception {
  const SseConnectionException(this.message);

  final String message;

  @override
  String toString() => 'SseConnectionException: $message';
}
