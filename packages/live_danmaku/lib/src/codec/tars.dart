import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Tars wire types.
abstract final class _T {
  static const int8 = 0;
  static const int16 = 1;
  static const int32 = 2;
  static const int64 = 3;
  static const float32 = 4;
  static const float64 = 5;
  static const string1 = 6;
  static const string4 = 7;
  static const map = 8;
  static const list = 9;
  static const structBegin = 10;
  static const structEnd = 11;
  static const zero = 12;
  static const simpleList = 13;
}

/// A Tars structure decoded without a schema (Huya's wire format): values by
/// tag. Integers are `int`, floats `double`, strings `String`, byte arrays
/// [Uint8List], lists `List<Object?>`, maps `Map<Object?, Object?>` and
/// nested structures [TarsStruct].
@immutable
final class TarsStruct {
  /// Wraps [fields].
  const new(this.fields);

  /// Decodes the fields of [bytes] up to their end; throws
  /// [FormatException] when truncated or malformed.
  factory decode(List<int> bytes) {
    final reader = _Reader(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    return reader.struct(0, topLevel: true);
  }

  /// Values by tag, in wire order.
  final Map<int, Object?> fields;

  /// The integer at [tag], or null.
  int? integer(int tag) => switch (fields[tag]) {
    final int value => value,
    _ => null,
  };

  /// The string at [tag], or null.
  String? string(int tag) => switch (fields[tag]) {
    final String value => value,
    _ => null,
  };

  /// The byte array at [tag], or null.
  Uint8List? bytes(int tag) => switch (fields[tag]) {
    final Uint8List value => value,
    _ => null,
  };

  /// The nested structure at [tag], or null.
  TarsStruct? struct(int tag) => switch (fields[tag]) {
    final TarsStruct value => value,
    _ => null,
  };

  /// The list at [tag], or empty.
  List<Object?> list(int tag) => switch (fields[tag]) {
    final List<Object?> value => value,
    _ => const [],
  };

  /// Encodes the fields back (smallest integer types, `string1` up to 255
  /// bytes), the form Huya's own writer produces.
  Uint8List encode() {
    final writer = TarsWriter();
    fields.forEach(writer.value);
    return writer.toBytes();
  }
}

/// Writes Tars fields.
final class TarsWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  void _head(int type, int tag) {
    if (tag < 0 || tag > 255) throw ArgumentError.value(tag, 'tag', 'out of range');
    if (tag < 15) {
      _out.addByte(tag << 4 | type);
    } else {
      _out
        ..addByte(0xF0 | type)
        ..addByte(tag);
    }
  }

  /// An integer field in the smallest type that holds it.
  void integer(int tag, int value) {
    if (value == 0) {
      _head(_T.zero, tag);
    } else if (value >= -128 && value <= 127) {
      _head(_T.int8, tag);
      _out.addByte(value & 0xFF);
    } else if (value >= -32768 && value <= 32767) {
      _head(_T.int16, tag);
      _out.add((ByteData(2)..setInt16(0, value)).buffer.asUint8List());
    } else if (value >= -2147483648 && value <= 2147483647) {
      _head(_T.int32, tag);
      _out.add((ByteData(4)..setInt32(0, value)).buffer.asUint8List());
    } else {
      _head(_T.int64, tag);
      _out.add((ByteData(8)..setInt64(0, value)).buffer.asUint8List());
    }
  }

  /// A UTF-8 string field.
  void string(int tag, String value) {
    final bytes = utf8.encode(value);
    if (bytes.length > 255) {
      _head(_T.string4, tag);
      _out.add((ByteData(4)..setInt32(0, bytes.length)).buffer.asUint8List());
    } else {
      _head(_T.string1, tag);
      _out.addByte(bytes.length);
    }
    _out.add(bytes);
  }

  /// A byte array (a simple list).
  void bytes(int tag, List<int> value) {
    _head(_T.simpleList, tag);
    _head(_T.int8, 0);
    integer(0, value.length);
    _out.add(value);
  }

  /// A list whose items [item] writes at tag 0.
  void list<T>(int tag, List<T> items, void Function(TarsWriter writer, T item) item) {
    _head(_T.list, tag);
    integer(0, items.length);
    for (final value in items) {
      item(this, value);
    }
  }

  /// A nested structure whose fields [fields] writes.
  void struct(int tag, void Function(TarsWriter writer) fields) {
    _head(_T.structBegin, tag);
    fields(this);
    _head(_T.structEnd, 0);
  }

  /// Any decoded value (see [TarsStruct]).
  void value(int tag, Object? data) {
    switch (data) {
      case final int number:
        integer(tag, number);
      case final double number:
        _head(_T.float64, tag);
        _out.add((ByteData(8)..setFloat64(0, number)).buffer.asUint8List());
      case final String text:
        string(tag, text);
      case final Uint8List data:
        bytes(tag, data);
      case final TarsStruct nested:
        struct(tag, (writer) => nested.fields.forEach(writer.value));
      case final List<Object?> items:
        list<Object?>(tag, items, (writer, item) => writer.value(0, item));
      case final Map<Object?, Object?> map:
        _head(_T.map, tag);
        integer(0, map.length);
        map.forEach((key, entry) {
          value(0, key);
          value(1, entry);
        });
      case null:
        break;
      default:
        throw ArgumentError.value(data, 'data', 'not a Tars value');
    }
  }

  /// The bytes written so far.
  Uint8List toBytes() => _out.toBytes();
}

final class _Reader {
  new(this._data);

  final Uint8List _data;
  var _offset = 0;
  var _depth = 0;

  static const _maxDepth = 32;

  bool get _atEnd => _offset >= _data.length;

  int _byte() {
    if (_atEnd) throw const FormatException('Truncated Tars data');
    return _data[_offset++];
  }

  ByteData _take(int size) {
    if (size < 0 || _offset + size > _data.length) throw const FormatException('Truncated Tars data');
    final view = ByteData.sublistView(_data, _offset, _offset + size);
    _offset += size;
    return view;
  }

  (int type, int tag) _head() {
    final byte = _byte();
    final type = byte & 0x0F;
    var tag = byte >> 4;
    if (tag == 15) tag = _byte();
    return (type, tag);
  }

  int _integer(int type) => switch (type) {
    _T.zero => 0,
    _T.int8 => _take(1).getInt8(0),
    _T.int16 => _take(2).getInt16(0),
    _T.int32 => _take(4).getInt32(0),
    _T.int64 => _take(8).getInt64(0),
    _ => throw FormatException('Expected a Tars integer, got type $type'),
  };

  int _length() {
    final (type, _) = _head();
    final length = _integer(type);
    if (length < 0 || length > _data.length) throw FormatException('Bad Tars length $length');
    return length;
  }

  Object? _value(int type) {
    switch (type) {
      case _T.int8 || _T.int16 || _T.int32 || _T.int64 || _T.zero:
        return _integer(type);
      case _T.float32:
        return _take(4).getFloat32(0);
      case _T.float64:
        return _take(8).getFloat64(0);
      case _T.string1:
        final length = _byte();
        return utf8.decode(Uint8List.sublistView(_take(length)), allowMalformed: true);
      case _T.string4:
        final length = _take(4).getInt32(0);
        return utf8.decode(Uint8List.sublistView(_take(length)), allowMalformed: true);
      case _T.map:
        final length = _length();
        final map = <Object?, Object?>{};
        for (var i = 0; i < length; i++) {
          final (keyType, _) = _head();
          final key = _value(keyType);
          final (valueType, _) = _head();
          map[key] = _value(valueType);
        }
        return map;
      case _T.list:
        final length = _length();
        final items = <Object?>[];
        for (var i = 0; i < length; i++) {
          final (itemType, _) = _head();
          items.add(_value(itemType));
        }
        return items;
      case _T.simpleList:
        _head();
        final length = _length();
        return Uint8List.fromList(Uint8List.sublistView(_take(length)));
      case _T.structBegin:
        return struct(_depth + 1);
      default:
        throw FormatException('Unknown Tars type $type');
    }
  }

  TarsStruct struct(int depth, {bool topLevel = false}) {
    if (depth > _maxDepth) throw const FormatException('Tars nesting too deep');
    final saved = _depth;
    _depth = depth;
    final fields = <int, Object?>{};
    try {
      while (!_atEnd) {
        final (type, tag) = _head();
        if (type == _T.structEnd) {
          if (topLevel) throw const FormatException('Unexpected Tars struct end');
          return TarsStruct(fields);
        }
        fields[tag] = _value(type);
      }
      if (!topLevel) throw const FormatException('Unterminated Tars struct');
      return TarsStruct(fields);
    } finally {
      _depth = saved;
    }
  }
}
