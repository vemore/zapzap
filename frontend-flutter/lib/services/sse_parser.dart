/// One dispatched server-sent event: its name (`message` when the stream
/// gave none) and its data, the `data:` lines joined with `\n`.
class SseMessage {
  const SseMessage({this.event = 'message', required this.data, this.id});

  final String event;
  final String data;
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is SseMessage &&
      other.event == event &&
      other.data == data &&
      other.id == id;

  @override
  int get hashCode => Object.hash(event, data, id);

  @override
  String toString() => 'SseMessage($event, $data)';
}

/// The `text/event-stream` line format, fed text in chunks of any size.
///
/// Follows the HTML standard's interpretation of the stream: lines end in
/// `\n`, `\r\n` or `\r`; a line starting with `:` is a comment (the
/// backends' heartbeat); `field: value` loses one space after the colon;
/// `data` lines accumulate; a blank line dispatches the event, unless it
/// has no data. `retry:` sets [retry] and is otherwise not acted on: the
/// client reconnects on its own delay.
class SseParser {
  final StringBuffer _line = StringBuffer();
  final StringBuffer _data = StringBuffer();
  bool _hasData = false;
  String _event = '';
  String? _id;
  bool _pendingCr = false;
  bool _started = false;

  /// The last `retry:` the stream sent, `null` until then.
  Duration? retry;

  /// Parses [chunk] and returns the events it completes. A line or an event
  /// cut between two chunks is kept until the next one.
  List<SseMessage> add(String chunk) {
    final out = <SseMessage>[];
    var text = chunk;
    if (!_started && text.isNotEmpty) {
      _started = true;
      if (text.startsWith('﻿')) text = text.substring(1);
    }
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (_pendingCr) {
        _pendingCr = false;
        if (char == '\n') continue; // the \n of a \r\n
      }
      if (char == '\r' || char == '\n') {
        _pendingCr = char == '\r';
        final message = _processLine(_line.toString());
        _line.clear();
        if (message != null) out.add(message);
      } else {
        _line.write(char);
      }
    }
    return out;
  }

  SseMessage? _processLine(String line) {
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return null;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        _event = value;
      case 'data':
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
      case 'id':
        if (!value.contains('\u0000')) _id = value;
      case 'retry':
        final ms = int.tryParse(value);
        if (ms != null && ms >= 0) retry = Duration(milliseconds: ms);
    }
    return null;
  }

  SseMessage? _dispatch() {
    final message = _hasData
        ? SseMessage(
            event: _event.isEmpty ? 'message' : _event,
            data: _data.toString(),
            id: _id,
          )
        : null;
    _data.clear();
    _hasData = false;
    _event = '';
    return message;
  }
}
