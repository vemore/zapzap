import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/services/sse_parser.dart';

void main() {
  group('SseParser', () {
    test('a named event and a default one', () {
      final parser = SseParser();
      expect(parser.add('event: event\ndata: {"a":1}\n\ndata: plain\n\n'), [
        const SseMessage(event: 'event', data: '{"a":1}'),
        const SseMessage(data: 'plain'),
      ]);
    });

    test('the event name does not leak into the next event', () {
      final parser = SseParser();
      parser.add('event: connected\ndata: x\n\n');
      expect(parser.add('data: y\n\n').single.event, 'message');
    });

    test('multi-line data is joined with \\n', () {
      final parser = SseParser();
      expect(
        parser.add('data: first\ndata:second\ndata:  third\n\n').single.data,
        'first\nsecond\n third',
      );
    });

    test('comments are ignored, even between the lines of an event', () {
      final parser = SseParser();
      expect(parser.add(': heartbeat 1726999999999\n\n'), isEmpty);
      expect(parser.add('event: event\n:heartbeat\ndata: x\n\n'), [
        const SseMessage(event: 'event', data: 'x'),
      ]);
    });

    test('a blank line without data dispatches nothing', () {
      final parser = SseParser();
      expect(parser.add('event: event\n\n\n'), isEmpty);
      expect(parser.add('data: x\n\n').single.event, 'message');
    });

    test('lines and events split across chunks, at any character', () {
      const stream =
          'retry: 1000\nevent: connected\ndata: {"type":"connected"}\n\n'
          ': heartbeat 1\n\n'
          'retry: 1000\nevent: event\ndata: {"partyId":"p1","action":"play"}\n\n';
      final whole = SseParser().add(stream);
      expect(whole, hasLength(2));
      for (var size = 1; size <= 7; size++) {
        final parser = SseParser();
        final got = <SseMessage>[];
        for (var i = 0; i < stream.length; i += size) {
          final end = i + size > stream.length ? stream.length : i + size;
          got.addAll(parser.add(stream.substring(i, end)));
        }
        expect(got, whole, reason: 'chunks of $size');
      }
    });

    test('an event is not dispatched before its blank line arrives', () {
      final parser = SseParser();
      expect(parser.add('event: event\ndata: {"a"'), isEmpty);
      expect(parser.add(':1}\n'), isEmpty);
      expect(parser.add('\n').single.data, '{"a":1}');
    });

    test(r'\r\n and \r line endings, a \r\n cut between chunks', () {
      final parser = SseParser();
      expect(parser.add('data: a\r\n\r\ndata: b\r\r').map((m) => m.data), [
        'a',
        'b',
      ]);
      expect(parser.add('data: c\r'), isEmpty);
      expect(parser.add('\n\r\n').single.data, 'c');
    });

    test('retry is read, a field without colon is a name only', () {
      final parser = SseParser();
      expect(parser.retry, isNull);
      parser.add('retry: 1000\ndata\n\n');
      expect(parser.retry, const Duration(milliseconds: 1000));
      parser.add('retry: soon\n');
      expect(parser.retry, const Duration(milliseconds: 1000));
    });

    test('id is kept, a leading byte-order mark is dropped', () {
      final parser = SseParser();
      expect(parser.add('﻿id: 7\ndata: x\n\n'), [
        const SseMessage(data: 'x', id: '7'),
      ]);
    });
  });
}
