import 'dart:convert';

import '../services/sse_parser.dart';
import 'json.dart';

/// A broadcast from the backend's one global stream (`/suscribeupdate`).
///
/// Every broadcast is the SSE event `event` with one JSON object
/// (`GameEvent`, `zapzap-rust/src/infrastructure/app_state.rs`): `{type,
/// partyId, userId, action?, timestamp, ...}`, the fields an event adds
/// flattened into it. Two families: a party or game change (`type` names it,
/// `partyId` its party), and presence (`type: userConnected |
/// userDisconnected`, `partyId: null`, `api/sse.rs`). A screen keeps those whose
/// [partyId] is its party.
class SseEvent {
  const SseEvent(this.data);

  /// The whole payload, for the fields an action adds (`handSize`...).
  final JsonMap data;

  /// The event of [message] when it is a backend broadcast (the SSE event
  /// `event`) carrying a JSON object; `null` otherwise (the initial
  /// `connected`, anything unreadable).
  static SseEvent? fromMessage(SseMessage message) {
    if (message.event != 'event') return null;
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
  bool get isPresence => type == 'userConnected' || type == 'userDisconnected';

  @override
  String toString() => 'SseEvent($data)';
}
