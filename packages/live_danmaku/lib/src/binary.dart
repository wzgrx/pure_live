import 'dart:math' as math;
import 'dart:typed_data';

/// Appends fixed-width numbers and bytes to a list (3.x
/// `core/common/binary_writer.dart`, used by the Bilibili and Douyu packet
/// headers).
///
/// Widths other than the ones a method supports write that many zero bytes,
/// as 3.x did; values wider than the field keep their low bytes.
final class BinaryWriter {
  /// Writes after the bytes already in [buffer] (a new list by default).
  new([List<int>? buffer]) : buffer = buffer ?? [];

  /// The bytes written so far.
  final List<int> buffer;

  /// Bytes written by this writer.
  int position = 0;

  /// Length of [buffer].
  int get length => buffer.length;

  /// Appends [bytes] as they are.
  void writeBytes(List<int> bytes) {
    buffer.addAll(bytes);
    position += bytes.length;
  }

  /// Appends [value] as a [width]-byte integer: 1 byte unsigned, 2, 4 or 8
  /// bytes two's complement in [endian] order.
  void writeInt(int value, int width, {Endian endian = Endian.big}) {
    final bytes = ByteData(width);
    switch (width) {
      case 1:
        bytes.setUint8(0, value.toUnsigned(8));
      case 2:
        bytes.setInt16(0, value, endian);
      case 4:
        bytes.setInt32(0, value, endian);
      case 8:
        bytes.setInt64(0, value, endian);
    }
    buffer.addAll(bytes.buffer.asUint8List());
    position += width;
  }

  /// Appends [value] as a 4-byte (float) or 8-byte (double) IEEE 754 number.
  void writeDouble(double value, int width, {Endian endian = Endian.big}) {
    final bytes = ByteData(width);
    switch (width) {
      case 4:
        bytes.setFloat32(0, value, endian);
      case 8:
        bytes.setFloat64(0, value, endian);
    }
    buffer.addAll(bytes.buffer.asUint8List());
    position += width;
  }
}

/// Reads fixed-width numbers and bytes from [buffer] in order (3.x
/// `BinaryReader`, same file as the writer).
///
/// One byte reads unsigned; 2, 4 and 8 bytes read two's complement. Reading
/// past the end throws a [RangeError].
final class BinaryReader {
  /// Reads [buffer] from the start.
  new(this.buffer);

  /// The bytes.
  final Uint8List buffer;

  /// Next byte to read.
  int position = 0;

  /// Length of [buffer].
  int get length => buffer.length;

  /// The next byte (0–255).
  int read() {
    final byte = buffer[position];
    position += 1;
    return byte;
  }

  /// The next [width]-byte integer; widths other than 1, 2, 4 and 8 read 0
  /// and skip [width] bytes.
  int readInt(int width, {Endian endian = Endian.big}) {
    final bytes = _take(width);
    return switch (width) {
      1 => bytes.getUint8(0),
      2 => bytes.getInt16(0, endian),
      4 => bytes.getInt32(0, endian),
      8 => bytes.getInt64(0, endian),
      _ => 0,
    };
  }

  /// The next byte.
  int readByte({Endian endian = Endian.big}) => readInt(1, endian: endian);

  /// The next 2-byte integer.
  int readShort({Endian endian = Endian.big}) => readInt(2, endian: endian);

  /// The next 4-byte integer.
  int readInt32({Endian endian = Endian.big}) => readInt(4, endian: endian);

  /// The next 8-byte integer.
  int readLong({Endian endian = Endian.big}) => readInt(8, endian: endian);

  /// A copy of the next [count] bytes.
  Uint8List readBytes(int count) {
    final bytes = Uint8List.fromList(buffer.sublist(position, position + count));
    position += count;
    return bytes;
  }

  /// The next 4-byte (float) or 8-byte (double) number; other widths read 0.
  double readFloat(int width, {Endian endian = Endian.big}) {
    final bytes = _take(width);
    return switch (width) {
      4 => bytes.getFloat32(0, endian),
      8 => bytes.getFloat64(0, endian),
      _ => 0,
    };
  }

  ByteData _take(int width) {
    final bytes = ByteData.sublistView(Uint8List.fromList(buffer.sublist(position, position + width)));
    position += width;
    return bytes;
  }
}

/// List helpers of 3.x (`core/common/utils/list_util.dart`; SOOP splits its
/// chat packets with [splitList]).
abstract final class ListUtil {
  /// [list] cut into runs of [size] items; the last run may be shorter.
  /// A [size] below 1 throws (3.x looped forever).
  static List<List<T>> subList<T>(List<T> list, int size) {
    if (size < 1) throw ArgumentError.value(size, 'size', 'Must be positive');
    return [
      for (var start = 0; start < list.length; start += size) list.sublist(start, math.min(start + size, list.length)),
    ];
  }

  /// [list] split at every [separator], which is dropped. Separators at the
  /// ends or next to each other give empty parts, like `String.split`; an
  /// empty list gives no parts.
  static List<List<T>> splitList<T>(List<T> list, T separator) {
    if (list.isEmpty) return [];
    final parts = <List<T>>[];
    var start = 0;
    for (var index = 0; index < list.length; index++) {
      if (list[index] == separator) {
        parts.add(list.sublist(start, index));
        start = index + 1;
      }
    }
    parts.add(list.sublist(start));
    return parts;
  }
}
