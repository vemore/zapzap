import 'package:flutter/foundation.dart';

import '../models/sse_event.dart';
import '../services/sse_client.dart';
import '../services/sse_transport.dart';

/// The real-time channel for the widget tree: one [SseClient] for the
/// whole signed-in session. Screens listen to [events] and keep their
/// party's; [connected] drives the connection indicator.
///
/// `appProviders` makes it follow `AuthProvider` ([follow]): connected with
/// the session's token on sign-in, closed on logout, reopened when the
/// token changes.
class SseProvider extends ChangeNotifier {
  SseProvider({
    required Uri uri,
    SseTransport? transport,
    Duration reconnectDelay = SseClient.defaultReconnectDelay,
  }) : _client = SseClient(
         uri: uri,
         transport: transport,
         reconnectDelay: reconnectDelay,
       ) {
    _client.onConnectedChanged = notifyListeners;
  }

  final SseClient _client;

  Stream<SseEvent> get events => _client.events;
  bool get connected => _client.connected;

  void connect(String token) => _client.connect(token);
  void disconnect() => _client.disconnect();

  /// [connect] with [token], or [disconnect] when it is `null`: what the
  /// session proxy in `appProviders` calls on every auth change.
  void follow(String? token) => token == null ? disconnect() : connect(token);

  @override
  void dispose() {
    _client.onConnectedChanged = null;
    _client.dispose();
    super.dispose();
  }
}
