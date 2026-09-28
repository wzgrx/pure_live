import 'dart:convert';
import 'dart:typed_data';

import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

void main() {
  group('BinaryWriter', () {
    test("writes 3.x's Bilibili packet header (big endian)", () {
      final body = utf8.encode('{"roomid":1}');
      final writer = BinaryWriter()
        ..writeInt(body.length + 16, 4)
        ..writeInt(16, 2)
        ..writeInt(0, 2)
        ..writeInt(7, 4)
        ..writeInt(1, 4)
        ..writeBytes(body);
      expect(writer.buffer.take(16), [0, 0, 0, 28, 0, 16, 0, 0, 0, 0, 0, 7, 0, 0, 0, 1]);
      expect(writer.buffer.skip(16), body);
      expect(writer.position, 28);
      expect(writer.length, 28);
    });

    test("writes 3.x's Douyu packet header (little endian, 1-byte fields)", () {
      const body = 'type@=mrkl/';
      final writer = BinaryWriter()
        ..writeInt(4 + 4 + body.length + 1, 4, endian: Endian.little)
        ..writeInt(4 + 4 + body.length + 1, 4, endian: Endian.little)
        ..writeInt(689, 2, endian: Endian.little)
        ..writeInt(0, 1, endian: Endian.little)
        ..writeInt(0, 1, endian: Endian.little)
        ..writeBytes(utf8.encode(body))
        ..writeInt(0, 1, endian: Endian.little);
      expect(writer.buffer.take(12), [20, 0, 0, 0, 20, 0, 0, 0, 0xB1, 0x02, 0, 0]);
      expect(utf8.decode(writer.buffer.sublist(12, 23)), body);
      expect(writer.buffer.last, 0);
      expect(writer.length, 24);
    });

    test('two’s complement for negative values in every width and order', () {
      expect((BinaryWriter()..writeInt(-1, 2)).buffer, [0xFF, 0xFF]);
      expect((BinaryWriter()..writeInt(-2, 4, endian: Endian.little)).buffer, [0xFE, 0xFF, 0xFF, 0xFF]);
      expect((BinaryWriter()..writeInt(-2, 4)).buffer, [0xFF, 0xFF, 0xFF, 0xFE]);
      expect((BinaryWriter()..writeInt(-1, 8)).buffer, List.filled(8, 0xFF));
      expect((BinaryWriter()..writeInt(0x01020304050607, 8, endian: Endian.little)).buffer, [7, 6, 5, 4, 3, 2, 1, 0]);
      expect((BinaryWriter()..writeInt(-1, 1)).buffer, [0xFF]);
    });

    test('values wider than the field keep their low bytes', () {
      expect((BinaryWriter()..writeInt(0x1FF, 1)).buffer, [0xFF]);
      expect((BinaryWriter()..writeInt(0x12345, 2)).buffer, [0x23, 0x45]);
      expect((BinaryWriter()..writeInt(0x1FFFFFFFF, 4)).buffer, [0xFF, 0xFF, 0xFF, 0xFF]);
    });

    test('other widths write that many zero bytes, as 3.x did', () {
      final writer = BinaryWriter()..writeInt(0x123456, 3);
      expect(writer.buffer, [0, 0, 0]);
      expect(writer.position, 3);
      expect((BinaryWriter()..writeDouble(1.5, 2)).buffer, [0, 0]);
    });

    test('floats and doubles in both orders', () {
      expect((BinaryWriter()..writeDouble(1.5, 4)).buffer, [0x3F, 0xC0, 0, 0]);
      expect((BinaryWriter()..writeDouble(1.5, 8, endian: Endian.little)).buffer, [0, 0, 0, 0, 0, 0, 0xF8, 0x3F]);
    });

    test('appends to a given buffer; position counts only its own bytes', () {
      final buffer = [9];
      final writer = BinaryWriter(buffer)..writeBytes([1, 2]);
      expect(buffer, [9, 1, 2]);
      expect(writer.position, 2);
      expect(writer.length, 3);
    });
  });

  group('BinaryReader', () {
    test('reads what the writer wrote', () {
      final writer = BinaryWriter()
        ..writeInt(200, 1)
        ..writeInt(-3, 2)
        ..writeInt(-4, 4, endian: Endian.little)
        ..writeInt(1 << 40, 8)
        ..writeDouble(2.5, 4)
        ..writeDouble(-0.25, 8, endian: Endian.little)
        ..writeBytes([7, 8, 9]);
      final reader = BinaryReader(Uint8List.fromList(writer.buffer));
      expect(reader.readByte(), 200);
      expect(reader.readShort(), -3);
      expect(reader.readInt32(endian: Endian.little), -4);
      expect(reader.readLong(), 1 << 40);
      expect(reader.readFloat(4), 2.5);
      expect(reader.readFloat(8, endian: Endian.little), -0.25);
      expect(reader.read(), 7);
      expect(reader.readBytes(2), [8, 9]);
      expect(reader.position, reader.length);
    });

    test('one byte reads unsigned, wider ones signed', () {
      final reader = BinaryReader(Uint8List.fromList([0xFF, 0xFF, 0xFE, 0x80, 0, 0, 0]));
      expect(reader.readInt(1), 255);
      expect(reader.readInt(2), -2);
      expect(reader.readInt(4), -0x80000000);
    });

    test('other widths read 0 and skip; reading past the end throws', () {
      final reader = BinaryReader(Uint8List.fromList([1, 2, 3, 4, 5, 6]));
      expect(reader.readInt(3), 0);
      expect(reader.position, 3);
      expect(reader.readFloat(2, endian: Endian.little), 0);
      expect(reader.position, 5);
      expect(reader.read(), 6);
      expect(reader.read, throwsRangeError);
      expect(() => reader.readBytes(1), throwsRangeError);
      expect(reader.position, 6);
    });

    test('a failed read leaves the position alone', () {
      final reader = BinaryReader(Uint8List.fromList([1]));
      expect(() => reader.readInt(2), throwsRangeError);
      expect(reader.position, 0);
      expect(reader.read(), 1);
      expect(reader.read, throwsRangeError);
      expect(reader.position, 1);
    });
  });

  group('ListUtil', () {
    test('splitList drops separators and keeps empty parts, like String.split', () {
      expect(ListUtil.splitList([1, 12, 2, 12, 12, 3], 12), [
        [1],
        [2],
        <int>[],
        [3],
      ]);
      expect(ListUtil.splitList([12, 1], 12), [
        <int>[],
        [1],
      ]);
      expect(ListUtil.splitList([1, 12], 12), [
        [1],
        <int>[],
      ]);
      expect(ListUtil.splitList([1, 2], 12), [
        [1, 2],
      ]);
      expect(ListUtil.splitList(<int>[], 12), isEmpty);
    });

    test('splitList cuts a SOOP chat body at 0x0C like 3.x', () {
      final body = utf8.encode('\x0c안녕\x0cuser\x0c\x0c');
      final fields = ListUtil.splitList(body, 0x0c).map(utf8.decode).toList();
      expect(fields, ['', '안녕', 'user', '', '']);
    });

    test('subList cuts runs of a size; the last may be shorter', () {
      expect(ListUtil.subList([1, 2, 3, 4, 5], 2), [
        [1, 2],
        [3, 4],
        [5],
      ]);
      expect(ListUtil.subList(<int>[], 2), isEmpty);
      expect(() => ListUtil.subList([1], 0), throwsArgumentError);
    });
  });
}
