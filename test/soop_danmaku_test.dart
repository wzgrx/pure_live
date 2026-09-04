import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/danmaku/soop_danmaku.dart';

void main() {
  List<int> packet(int service, List<String> fields) {
    final body = utf8.encode(fields.join('\x0c'));
    return <int>[
      0x1b,
      0x09,
      ...ascii.encode(service.toString().padLeft(4, '0')),
      ...ascii.encode(body.length.toString().padLeft(6, '0')),
      ...ascii.encode('00'),
      ...body,
    ];
  }

  test('SOOP decoder emits only SVC_CHATMESG packets', () {
    final danmaku = SoopDanmaku();
    final messages = <LiveMessage>[];
    danmaku.onMessage = messages.add;

    danmaku.decodeMessage(<int>[
      ...packet(4, <String>['', 'healeroflove', '', '', '', '', 'fw=-1&afw=-1', '']),
      ...packet(5, <String>['', 'hello', '', '', '', '', 'viewer', '']),
    ]);

    expect(messages, hasLength(1));
    expect(messages.single.message, 'hello');
    expect(messages.single.userName, 'viewer');
  });

  test('SOOP decoder handles multiple chat packets in one WebSocket payload', () {
    final danmaku = SoopDanmaku();
    final messages = <LiveMessage>[];
    danmaku.onMessage = messages.add;

    danmaku.decodeMessage(<int>[
      ...packet(5, <String>['', 'first', '', '', '', '', 'one', '']),
      ...packet(5, <String>['', 'second', '', '', '', '', 'two', '']),
    ]);

    expect(messages.map((message) => '${message.userName}:${message.message}'), <String>['one:first', 'two:second']);
  });

  test('SOOP decoder ignores a truncated packet without emitting data', () {
    final danmaku = SoopDanmaku();
    final messages = <LiveMessage>[];
    danmaku.onMessage = messages.add;
    final truncated = packet(5, <String>['', 'partial', '', '', '', '', 'viewer', ''])..removeLast();

    expect(() => danmaku.decodeMessage(truncated), returnsNormally);
    expect(messages, isEmpty);
  });
}
