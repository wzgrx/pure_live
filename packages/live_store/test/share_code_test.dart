import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

List<int> str(String text) {
  final bytes = utf8.encode(text);
  return [0xa0 | bytes.length, ...bytes];
}

String code(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

void main() {
  test('encodes the 3.x MessagePack layout (store.md §8)', () {
    final bytes = [
      0x88,
      ...str('m'),
      ...str('pure_live'),
      ...str('p'),
      ...str('douyu'),
      ...str('r'),
      ...str('5526219'),
      ...str('ti'),
      ...str(''),
      ...str('n'),
      ...str('A'),
      ...str('l'),
      ...str(''),
      ...str('c'),
      ...str(''),
      ...str('a'),
      ...str(''),
    ];
    expect(ShareCode(RoomRef('douyu', '5526219'), anchorName: 'A').encode(), code(bytes));
  });

  test('round-trips long and non-ASCII text', () {
    final original = ShareCode(
      RoomRef('bilibili', '22603245'),
      title: '今晚的直播' * 20,
      anchorName: '主播',
      link: 'https://live.bilibili.com/22603245',
      cover: 'https://example.invalid/${'c' * 300}.jpg',
    );
    final decoded = ShareCode.decode(original.encode())!;
    expect(decoded.ref, original.ref);
    expect(decoded.title, original.title);
    expect(decoded.anchorName, '主播');
    expect(decoded.cover, original.cover);
  });

  test('accepts padded standard base64 and integer room ids', () {
    final bytes = [0x83, ...str('m'), ...str('pure_live'), ...str('p'), ...str('Huya'), ...str('r'), 0xcd, 0x03, 0xe6];
    final standard = base64.encode(bytes);
    final decoded = ShareCode.decode(' $standard ')!;
    expect(decoded.ref, RoomRef('huya', '998'));
    expect(decoded.title, '');
  });

  test('rejects other text', () {
    expect(ShareCode.decode(''), isNull);
    expect(ShareCode.decode('hello world'), isNull);
    expect(ShareCode.decode(code([0x81, ...str('m'), ...str('other')])), isNull);
    expect(ShareCode.decode(code([0x82, ...str('m'), ...str('pure_live'), ...str('r'), ...str('0')])), isNull);
    expect(ShareCode.decode(code([0x88, ...str('m')])), isNull, reason: 'truncated');
    expect(ShareCode.decode(code([0x91, 0x01])), isNull, reason: 'unsupported array');
  });
}
