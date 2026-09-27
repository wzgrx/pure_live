import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One protobuf field as it appeared on the wire.
@immutable
final class ProtoField {
  /// Creates a field.
  const new(this.number, this.wireType, this.value);

  /// Field number.
  final int number;

  /// Wire type: 0 varint, 1 fixed64, 2 length-delimited, 5 fixed32.
  final int wireType;

  /// `int` for varint and fixed types, [Uint8List] for length-delimited.
  final Object value;
}

/// A protobuf message decoded without a schema: the fields in wire order
/// (docs/adr/0019-danmaku-layer.md: a hand-written reader of the few fields the
/// connectors need instead of generated classes).
@immutable
final class ProtoMessage {
  /// Wraps [fields].
  const new(this.fields);

  /// Decodes [bytes]; throws [FormatException] on truncated or group fields.
  factory decode(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final fields = <ProtoField>[];
    var offset = 0;
    int varint() {
      var result = 0;
      for (var shift = 0; shift < 64; shift += 7) {
        if (offset >= data.length) throw const FormatException('Truncated varint');
        final byte = data[offset++];
        result |= (byte & 0x7F) << shift;
        if (byte < 0x80) return result;
      }
      throw const FormatException('Varint longer than 10 bytes');
    }

    int fixed(int size) {
      if (offset + size > data.length) throw const FormatException('Truncated fixed field');
      final view = ByteData.sublistView(data, offset, offset + size);
      offset += size;
      return size == 8 ? view.getInt64(0, Endian.little) : view.getUint32(0, Endian.little);
    }

    while (offset < data.length) {
      final key = varint();
      final number = key >>> 3;
      final wireType = key & 7;
      if (number == 0) throw const FormatException('Field number 0');
      switch (wireType) {
        case 0:
          fields.add(ProtoField(number, 0, varint()));
        case 1:
          fields.add(ProtoField(number, 1, fixed(8)));
        case 2:
          final length = varint();
          if (length < 0 || offset + length > data.length) throw const FormatException('Truncated bytes field');
          fields.add(ProtoField(number, 2, Uint8List.sublistView(data, offset, offset + length)));
          offset += length;
        case 5:
          fields.add(ProtoField(number, 5, fixed(4)));
        default:
          throw FormatException('Unsupported wire type $wireType');
      }
    }
    return ProtoMessage(fields);
  }

  /// Fields in wire order.
  final List<ProtoField> fields;

  ProtoField? _last(int number) {
    for (var i = fields.length - 1; i >= 0; i--) {
      if (fields[i].number == number) return fields[i];
    }
    return null;
  }

  /// The last varint or fixed value of [number]; null when absent.
  int? integer(int number) => switch (_last(number)?.value) {
    final int value => value,
    _ => null,
  };

  /// Whether [number] is a true bool.
  bool flag(int number) => (integer(number) ?? 0) != 0;

  /// The last length-delimited value of [number].
  Uint8List? bytes(int number) => switch (_last(number)?.value) {
    final Uint8List value => value,
    _ => null,
  };

  /// The last value of [number] as UTF-8 text; malformed bytes become U+FFFD.
  String? string(int number) {
    final value = bytes(number);
    return value == null ? null : utf8.decode(value, allowMalformed: true);
  }

  /// The last value of [number] as a nested message.
  ProtoMessage? message(int number) {
    final value = bytes(number);
    return value == null ? null : ProtoMessage.decode(value);
  }

  /// Every value of a repeated [number], as nested messages.
  Iterable<ProtoMessage> messages(int number) sync* {
    for (final field in fields) {
      if (field.number == number && field.value is Uint8List) yield ProtoMessage.decode(field.value as Uint8List);
    }
  }
}

/// Writes protobuf fields in call order.
final class ProtoWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  void _varint(int value) {
    var rest = value;
    while (true) {
      final byte = rest & 0x7F;
      rest >>>= 7;
      if (rest == 0) {
        _out.addByte(byte);
        return;
      }
      _out.addByte(byte | 0x80);
    }
  }

  /// A varint field (int, uint, bool, enum).
  void integer(int number, int value) {
    _varint(number << 3);
    _varint(value);
  }

  /// A length-delimited field.
  void bytes(int number, List<int> value) {
    _varint(number << 3 | 2);
    _varint(value.length);
    _out.add(value);
  }

  /// A UTF-8 string field.
  void string(int number, String value) => bytes(number, utf8.encode(value));

  /// Copies [field] as it was read.
  void field(ProtoField field) {
    switch (field.value) {
      case final Uint8List value:
        bytes(field.number, value);
      case final int value when field.wireType == 0:
        integer(field.number, value);
      case final int value:
        _varint(field.number << 3 | field.wireType);
        final size = field.wireType == 1 ? 8 : 4;
        final data = ByteData(size);
        if (size == 8) {
          data.setInt64(0, value, Endian.little);
        } else {
          data.setUint32(0, value, Endian.little);
        }
        _out.add(data.buffer.asUint8List());
    }
  }

  /// The encoded message.
  Uint8List toBytes() => _out.toBytes();
}
