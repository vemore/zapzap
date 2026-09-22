import 'dart:async';

import 'package:zapzap/services/sse_parser.dart';
import 'package:zapzap/services/sse_transport.dart';

/// A transport whose connections the test drives by hand.
class FakeSseTransport implements SseTransport {
  final List<FakeSseConnection> connections = [];

  FakeSseConnection get last => connections.last;

  @override
  Stream<SseMessage> connect(Uri uri, {void Function()? onOpen}) {
    final connection = FakeSseConnection(uri, onOpen);
    connections.add(connection);
    return connection._controller.stream;
  }
}

class FakeSseConnection {
  FakeSseConnection(this.uri, this._onOpen) {
    _controller = StreamController<SseMessage>(
      onCancel: () => cancelled = true,
    );
  }

  final Uri uri;
  final void Function()? _onOpen;
  late final StreamController<SseMessage> _controller;
  bool cancelled = false;

  void open() => _onOpen?.call();

  void send(String data, {String event = 'event'}) =>
      _controller.add(SseMessage(event: event, data: data));

  void fail() {
    _controller.addError(const SseConnectionException('test'));
    _controller.close();
  }

  void end() => _controller.close();
}
