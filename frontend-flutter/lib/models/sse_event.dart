import 'dart:convert';

import '../services/sse_parser.dart';
import 'json.dart';

/// A broadcast from the backend's one global stream (`/suscribeupdate`).
///
/// Two families, both sent as the SSE event `event` with a JSON object:
/// a party or game change, `{partyId, userId, action, ...}` (Node) or the
/// same with a `type` (Rust); and presence, `{type: userConnected |
/// userDisconnected | userStatusChanged, userId, ...}`. Every client gets
/// every event: a screen keeps those whose [partyId] is its party.
class SseEvent {
  const SseEvent(this.data);

  /// The whole payload, for the fields an action adds (`handSize`...).
  final JsonMap data;

  /// The event of [message] when it is a backend broadcast (`event` or an
  /// unnamed `message`) carrying a JSON object; `null` otherwise (the
  /// initial `connected`, anything unreadable).
  static SseEvent? fromMessage(SseMessage message) {
    if (message.event != 'event' && message.event != 'message') return null;
    try {
      final decoded = jsonDecode(message.data);
      return decoded is Map ? SseEvent(decoded.cast<String, dynamic>()) : null;
    } on FormatException {
      return null;
    }
  }

  String? get type => Json.stringOrNull(data, 'type');
  String? get partyId => Json.stringOrNull(data, 'partyId');
  String? get userId => Json.stringOrNull(data, 'userId');
  String? get action => Json.stringOrNull(data, 'action');
  DateTime? get timestamp => Json.timestamp(data, 'timestamp');

  /// A presence change rather than a party or game one.
  bool get isPresence =>
      type == 'userConnected' ||
      type == 'userDisconnected' ||
      type == 'userStatusChanged';

  @override
  String toString() => 'SseEvent($data)';
}
