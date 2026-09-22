import 'dart:async';

import '../models/sse_event.dart';
import 'sse_parser.dart';
import 'sse_transport.dart';

/// The one real-time connection of a signed-in session, the counterpart of
/// the React `useSSE` hook, in plain Dart.
///
/// [connect] opens `<uri>?token=<jwt>` — with the token the backend counts
/// the user as online (presence) — and keeps it open: when it fails or
/// ends, it is reopened [reconnectDelay] later (3 s, as in React), until
/// [disconnect].
class SseClient {
  SseClient({
    required this.uri,
    SseTransport? transport,
    this.reconnectDelay = defaultReconnectDelay,
  }) : _transport = transport ?? createPlatformTransport();

  static const Duration defaultReconnectDelay = Duration(seconds: 3);

  final Uri uri;
  final Duration reconnectDelay;
  final SseTransport _transport;
  final StreamController<SseEvent> _events =
      StreamController<SseEvent>.broadcast();

  StreamSubscription<SseMessage>? _subscription;
  Timer? _retryTimer;
  // Bumped on every open and close, so a late callback of an old
  // connection is ignored.
  int _generation = 0;
  String? _token;
  bool _connected = false;

  /// Called whenever [connected] changes.
  void Function()? onConnectedChanged;

  /// Every backend broadcast, across reconnections.
  Stream<SseEvent> get events => _events.stream;

  /// Whether the stream is open now.
  bool get connected => _connected;

  /// The token of the current session, `null` once disconnected.
  String? get token => _token;

  /// Opens the connection for [token]; a different token replaces the
  /// current connection, the same one keeps it.
  void connect(String token) {
    if (token == _token) return;
    _close();
    _token = token;
    _open();
  }

  /// Closes the connection and stops reconnecting.
  void disconnect() {
    _token = null;
    _close();
  }

  /// [disconnect], then ends [events].
  Future<void> dispose() {
    disconnect();
    return _events.close();
  }

  void _open() {
    final generation = ++_generation;
    final target = uri.replace(
      queryParameters: {...uri.queryParameters, 'token': _token!},
    );
    _subscription = _transport
        .connect(
          target,
          onOpen: () {
            if (generation == _generation) _setConnected(true);
          },
        )
        .listen(
          (message) {
            if (generation != _generation) return;
            final event = SseEvent.fromMessage(message);
            if (event != null) _events.add(event);
          },
          onError: (Object _) {
            if (generation == _generation) _lost();
          },
          onDone: () {
            if (generation == _generation) _lost();
          },
          cancelOnError: true,
        );
  }

  void _lost() {
    _generation++;
    _subscription?.cancel();
    _subscription = null;
    _setConnected(false);
    _retryTimer = Timer(reconnectDelay, () {
      if (_token != null) _open();
    });
  }

  void _close() {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _setConnected(false);
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onConnectedChanged?.call();
  }
}
