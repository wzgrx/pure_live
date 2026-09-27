import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Tars wire types (legacy lib/pkg/tars/codec/tars_struct.dart).
abstract final class _Type {
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

/// Writes Tars fields byte for byte like the legacy `TarsOutputStream`:
/// the smallest integer type (0 as a zero tag), `string1` up to 255 UTF-8
/// bytes, byte arrays as simple lists.
final class TarsWriter {
  final BytesBuilder _bytes = BytesBuilder();

  void _head(int type, int tag) {
    if (tag < 0 || tag > 255) throw ArgumentError.value(tag, 'tag', 'out of range');
    if (tag < 15) {
      _bytes.addByte(tag << 4 | type);
    } else {
      _bytes
        ..addByte(0xF0 | type)
        ..addByte(tag);
    }
  }

  /// An integer field.
  void writeInt(int tag, int value) {
    if (value == 0) {
      _head(_Type.zero, tag);
    } else if (value >= -128 && value <= 127) {
      _head(_Type.int8, tag);
      _bytes.addByte(value & 0xFF);
    } else if (value >= -32768 && value <= 32767) {
      _head(_Type.int16, tag);
      _bytes.add((ByteData(2)..setInt16(0, value)).buffer.asUint8List());
    } else if (value >= -2147483648 && value <= 2147483647) {
      _head(_Type.int32, tag);
      _bytes.add((ByteData(4)..setInt32(0, value)).buffer.asUint8List());
    } else {
      _head(_Type.int64, tag);
      _bytes.add((ByteData(8)..setInt64(0, value)).buffer.asUint8List());
    }
  }

  /// A UTF-8 string field.
  void writeString(int tag, String value) {
    final bytes = utf8.encode(value);
    if (bytes.length > 255) {
      _head(_Type.string4, tag);
      _bytes.add((ByteData(4)..setInt32(0, bytes.length)).buffer.asUint8List());
    } else {
      _head(_Type.string1, tag);
      _bytes.addByte(bytes.length);
    }
    _bytes.add(bytes);
  }

  /// A byte array field (a simple list of bytes).
  void writeBytes(int tag, List<int> value) {
    _head(_Type.simpleList, tag);
    _head(_Type.int8, 0);
    writeInt(0, value.length);
    _bytes.add(value);
  }

  /// A nested structure whose fields [fields] writes.
  void writeStruct(int tag, void Function(TarsWriter writer) fields) {
    _head(_Type.structBegin, tag);
    fields(this);
    _head(_Type.structEnd, 0);
  }

  /// A map; keys are written at tag 0 and values at tag 1.
  void writeMap<K, V>(
    int tag,
    Map<K, V> map, {
    required void Function(TarsWriter writer, int tag, K key) key,
    required void Function(TarsWriter writer, int tag, V value) value,
  }) {
    _head(_Type.map, tag);
    writeInt(0, map.length);
    for (final entry in map.entries) {
      key(this, 0, entry.key);
      value(this, 1, entry.value);
    }
  }

  /// The bytes written so far.
  Uint8List toBytes() => _bytes.toBytes();
}

/// A decoded Tars structure: field values by tag. Integers are `int`, floats
/// `double`, strings `String`, simple lists `Uint8List`, lists `List`, maps
/// `Map` and nested structures [TarsStruct].
@immutable
final class TarsStruct {
  /// Wraps decoded [fields].
  const new(this.fields);

  /// Decodes the fields of [bytes] up to their end.
  factory decode(List<int> bytes) => _TarsReader(bytes).fields(0);

  /// Field values by tag.
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

  /// The byte array at [tag] (a simple list, or a list of small integers),
  /// or null.
  Uint8List? bytes(int tag) => _asBytes(fields[tag]);

  /// The structure at [tag], or null.
  TarsStruct? struct(int tag) => switch (fields[tag]) {
    final TarsStruct value => value,
    _ => null,
  };

  /// The map at [tag], or null.
  Map<Object?, Object?>? map(int tag) => switch (fields[tag]) {
    final Map<Object?, Object?> value => value,
    _ => null,
  };

  static Uint8List? _asBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List && value.every((item) => item is int && item >= -128 && item <= 255)) {
      return Uint8List.fromList([for (final item in value) (item as int) & 0xFF]);
    }
    return null;
  }
}

/// Reads Tars fields; malformed input is a [FormatException].
final class _TarsReader {
  new(List<int> bytes) : _data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  final Uint8List _data;
  int _position = 0;

  static const _maxDepth = 32;

  Never _fail(String reason) => throw FormatException('Tars: $reason', null, _position);

  int _byte() {
    if (_position >= _data.length) _fail('unexpected end');
    return _data[_position++];
  }

  ByteData _take(int length) {
    if (length < 0 || _position + length > _data.length) _fail('length $length beyond the buffer');
    final view = ByteData.sublistView(_data, _position, _position + length);
    _position += length;
    return view;
  }

  (int, int) _head() {
    final first = _byte();
    final type = first & 0x0F;
    var tag = first >> 4;
    if (tag == 15) tag = _byte();
    return (type, tag);
  }

  /// Fields until the end of the buffer or a structure end (consumed).
  TarsStruct fields(int depth) {
    if (depth > _maxDepth) _fail('nested too deep');
    final fields = <int, Object?>{};
    while (_position < _data.length) {
      final (type, tag) = _head();
      if (type == _Type.structEnd) {
        if (depth == 0) _fail('unbalanced structure end');
        return TarsStruct(fields);
      }
      fields[tag] = _value(type, depth);
    }
    if (depth > 0) _fail('unterminated structure');
    return TarsStruct(fields);
  }

  int _size() {
    final (type, _) = _head();
    final size = _integer(type);
    if (size < 0 || size > _data.length - _position) _fail('size $size');
    return size;
  }

  int _integer(int type) => switch (type) {
    _Type.zero => 0,
    _Type.int8 => _take(1).getInt8(0),
    _Type.int16 => _take(2).getInt16(0),
    _Type.int32 => _take(4).getInt32(0),
    _Type.int64 => _take(8).getInt64(0),
    _ => _fail('type $type is not an integer'),
  };

  Object? _value(int type, int depth) {
    switch (type) {
      case _Type.zero || _Type.int8 || _Type.int16 || _Type.int32 || _Type.int64:
        return _integer(type);
      case _Type.float32:
        return _take(4).getFloat32(0);
      case _Type.float64:
        return _take(8).getFloat64(0);
      case _Type.string1:
        return _string(_byte());
      case _Type.string4:
        return _string(_take(4).getInt32(0));
      case _Type.map:
        final size = _size();
        final map = <Object?, Object?>{};
        for (var i = 0; i < size; i++) {
          final key = _element(0, depth);
          map[key] = _element(1, depth);
        }
        return map;
      case _Type.list:
        final size = _size();
        return [for (var i = 0; i < size; i++) _element(0, depth)];
      case _Type.simpleList:
        final (elementType, _) = _head();
        if (elementType != _Type.int8) _fail('simple list of type $elementType');
        final length = _size();
        final view = _take(length);
        return Uint8List.fromList(view.buffer.asUint8List(view.offsetInBytes, length));
      case _Type.structBegin:
        return fields(depth + 1);
      default:
        _fail('unknown type $type');
    }
  }

  Object? _element(int expectedTag, int depth) {
    final (type, tag) = _head();
    if (tag != expectedTag) _fail('element tag $tag, expected $expectedTag');
    if (type == _Type.structEnd) _fail('structure end inside a container');
    return _value(type, depth);
  }

  String _string(int length) {
    final view = _take(length);
    return utf8.decode(view.buffer.asUint8List(view.offsetInBytes, length), allowMalformed: true);
  }
}

/// One TUP3 packet: the legacy `TarsUniPacket` over `RequestPacket`
/// (lib/pkg/tars/tup, base_tars_http.dart:87-107).
@immutable
final class WupPacket {
  /// Creates a packet; [params] maps a parameter name to its encoded value
  /// (a Tars field at tag 0).
  const new({required this.servant, required this.function, required this.params, this.requestId = 0});

  /// Decodes a packet: a 4-byte big-endian length, then the `RequestPacket`
  /// fields; the parameters are the map in `sBuffer` (tag 7).
  factory decode(List<int> bytes) {
    if (bytes.length < 4) throw const FormatException('WUP: shorter than its length prefix');
    final packet = TarsStruct.decode(bytes.sublist(4));
    final version = packet.integer(1);
    if (version != 3) throw FormatException('WUP: version $version, expected TUP3');
    final buffer = packet.bytes(7);
    if (buffer == null) throw const FormatException('WUP: no sBuffer');
    final raw = TarsStruct.decode(buffer).map(0);
    if (raw == null) throw const FormatException('WUP: sBuffer is not a map');
    final params = <String, Uint8List>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = TarsStruct._asBytes(entry.value);
      if (key is! String || value == null) throw const FormatException('WUP: parameter is not name → bytes');
      params[key] = value;
    }
    return WupPacket(
      servant: packet.string(5) ?? '',
      function: packet.string(6) ?? '',
      params: params,
      requestId: packet.integer(4) ?? 0,
    );
  }

  /// Servant name (`liveui`).
  final String servant;

  /// Function name (`getCdnTokenInfoEx`).
  final String function;

  /// Parameters by name; each value is one Tars field at tag 0.
  final Map<String, List<int>> params;

  /// Request id; Huya's calls use 0.
  final int requestId;

  /// A parameter holding a structure: the structure at tag 0.
  static Uint8List structParam(void Function(TarsWriter writer) fields) =>
      (TarsWriter()..writeStruct(0, fields)).toBytes();

  /// A parameter holding an integer at tag 0 (the return code `""`).
  static Uint8List intParam(int value) => (TarsWriter()..writeInt(0, value)).toBytes();

  /// Encodes the packet: version 3, normal call, no timeout, empty context
  /// and status.
  Uint8List encode() {
    final buffer = TarsWriter()
      ..writeMap<String, List<int>>(
        0,
        params,
        key: (writer, tag, key) => writer.writeString(tag, key),
        value: (writer, tag, value) => writer.writeBytes(tag, value),
      );
    void emptyMap(TarsWriter writer, int tag) => writer.writeMap<String, String>(
      tag,
      const {},
      key: (writer, tag, key) => writer.writeString(tag, key),
      value: (writer, tag, value) => writer.writeString(tag, value),
    );
    final body = TarsWriter()
      ..writeInt(1, 3)
      ..writeInt(2, 0)
      ..writeInt(3, 0)
      ..writeInt(4, requestId)
      ..writeString(5, servant)
      ..writeString(6, function)
      ..writeBytes(7, buffer.toBytes())
      ..writeInt(8, 0);
    emptyMap(body, 9);
    emptyMap(body, 10);
    final bytes = body.toBytes();
    return (BytesBuilder(copy: false)
          ..add((ByteData(4)..setInt32(0, bytes.length + 4)).buffer.asUint8List())
          ..add(bytes))
        .toBytes();
  }
}

/// The `HuyaUserId` Tars structure (legacy lib/core/tars/types.dart:6-37).
@immutable
final class HuyaUserId {
  /// Creates an identity; every field defaults to empty or 0.
  const new({
    this.uid = 0,
    this.guid = '',
    this.token = '',
    this.huyaUa = '',
    this.cookie = '',
    this.tokenType = 0,
    this.deviceInfo = '',
    this.qimei = '',
  });

  /// tag 0 `lUid`.
  final int uid;

  /// tag 1 `sGuid`.
  final String guid;

  /// tag 2 `sToken`.
  final String token;

  /// tag 3 `sHuYaUA`.
  final String huyaUa;

  /// tag 4 `sCookie`.
  final String cookie;

  /// tag 5 `iTokenType`.
  final int tokenType;

  /// tag 6 `sDeviceInfo`.
  final String deviceInfo;

  /// tag 7 `sQIMEI`.
  final String qimei;

  /// Writes the fields in tag order.
  void writeTo(TarsWriter writer) => writer
    ..writeInt(0, uid)
    ..writeString(1, guid)
    ..writeString(2, token)
    ..writeString(3, huyaUa)
    ..writeString(4, cookie)
    ..writeInt(5, tokenType)
    ..writeString(6, deviceInfo)
    ..writeString(7, qimei);

  /// Diagnostics without the cookie or GUID (spec §6.7).
  @override
  String toString() => 'HuyaUserId($huyaUa)';
}

/// `liveui.getCdnTokenInfoEx` (spec/sites/huya.md §6.2, §6.3).
abstract final class HuyaCdnTokenCall {
  /// Servant.
  static const servant = 'liveui';

  /// Function.
  static const function = 'getCdnTokenInfoEx';

  /// The request packet for `GetCdnTokenExReq` (tags: 0 sFlvUrl,
  /// 1 sStreamName, 2 iLoopTime, 3 tId, 4 iAppId; get_cdn_token_ex_req.dart).
  static Uint8List request({
    required String flvUrl,
    required String streamName,
    required HuyaUserId userId,
    int loopTime = 0,
    int appId = 66,
  }) => WupPacket(
    servant: servant,
    function: function,
    params: {
      'tReq': WupPacket.structParam(
        (writer) => writer
          ..writeString(0, flvUrl)
          ..writeString(1, streamName)
          ..writeInt(2, loopTime)
          ..writeStruct(3, userId.writeTo)
          ..writeInt(4, appId),
      ),
    },
  ).encode();

  /// The response: return code `""` (0 when absent, as the legacy
  /// `respPack.get("", 0)`), and `GetCdnTokenExResp` in `tRsp` (tag 0
  /// sFlvToken, tag 1 iExpireTime). Malformed bytes are a [FormatException].
  static ({int code, String token, int expireTime}) response(List<int> bytes) {
    final packet = WupPacket.decode(bytes);
    final codeBytes = packet.params[''];
    final code = codeBytes == null ? 0 : TarsStruct.decode(codeBytes).integer(0) ?? 0;
    final rspBytes = packet.params['tRsp'];
    final rsp = rspBytes == null ? null : TarsStruct.decode(rspBytes).struct(0);
    if (code == 0 && rsp == null) throw const FormatException('getCdnTokenInfoEx: no tRsp');
    return (code: code, token: rsp?.string(0) ?? '', expireTime: rsp?.integer(1) ?? 0);
  }
}
