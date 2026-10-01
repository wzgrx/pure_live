import 'dart:convert';
import 'dart:typed_data';

/// Reads a 3.x Hive box file (`app_settings.hive`, written by hive_ce 2.x)
/// without Hive: the file is only read, never opened as a box, so no lock
/// file is created and nothing is compacted or truncated.
///
/// The format is an append-only log of frames: `u32 length`, the key
/// (`0` + u32, or `1` + u8 length + UTF-8), the value (absent for a
/// deletion), and a CRC-32 of everything before it. The last frame of a key
/// wins. Like Hive, reading stops at the first incomplete or corrupt frame
/// and keeps what came before it. 3.x registered no type adapters, so only
/// Hive's built-in types occur.
abstract final class HiveBoxReader {
  /// The box's entries; integer keys are returned as their decimal text.
  static Map<String, Object?> read(Uint8List bytes) {
    final entries = <String, Object?>{};
    var offset = 0;
    final data = ByteData.sublistView(bytes);
    while (bytes.length - offset >= 4) {
      final length = data.getUint32(offset, Endian.little);
      if (length < 8 || bytes.length - offset < length) break;
      final crc = data.getUint32(offset + length - 4, Endian.little);
      if (_crc32(bytes, offset, length - 4) != crc) break;
      final frame = _Reader(bytes, offset + 4, offset + length - 4);
      try {
        final key = frame.key();
        if (frame.atEnd) {
          entries.remove(key);
        } else {
          entries[key] = frame.value();
        }
      } on FormatException {
        break;
      }
      offset += length;
    }
    return entries;
  }

  static final List<int> _table = List.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(Uint8List bytes, int offset, int length) {
    var crc = 0xFFFFFFFF;
    for (var i = offset; i < offset + length; i++) {
      crc = _table[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}

final class _Reader {
  new(this._bytes, this._offset, this._end) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _offset;
  final int _end;

  bool get atEnd => _offset >= _end;

  void _need(int count) {
    if (_offset + count > _end) throw const FormatException('Hive frame too short');
  }

  int _byte() {
    _need(1);
    return _bytes[_offset++];
  }

  int _uint32() {
    _need(4);
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  double _double() {
    _need(8);
    final value = _data.getFloat64(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  String _string([int? byteCount]) {
    final count = byteCount ?? _uint32();
    _need(count);
    final text = utf8.decode(Uint8List.sublistView(_bytes, _offset, _offset + count), allowMalformed: true);
    _offset += count;
    return text;
  }

  String key() => switch (_byte()) {
    0 => '${_uint32()}',
    1 => _string(_byte()),
    _ => throw const FormatException('Unsupported Hive key type'),
  };

  List<Object?> _list(Object? Function() item) => [for (var i = _uint32(); i > 0; i--) item()];

  Object? value() {
    var type = _byte();
    if (type == 21) {
      _need(2);
      type = _bytes[_offset] | _bytes[_offset + 1] << 8;
      _offset += 2;
    }
    return switch (type) {
      0 => null,
      1 => _intFrom(_double()),
      2 => _double(),
      3 => _byte() > 0,
      4 => _string(),
      5 => Uint8List.fromList(_list(_byte).cast<int>()),
      6 => _list(() => _intFrom(_double())).cast<int>(),
      7 => _list(_double).cast<double>(),
      8 => _list(() => _byte() > 0).cast<bool>(),
      9 => _list(_string).cast<String>(),
      10 => _list(value),
      11 => {for (var i = _uint32(); i > 0; i--) value(): value()},
      13 => _list(() => _intFrom(_double())).cast<int>().toSet(),
      14 => _list(_double).cast<double>().toSet(),
      15 => _list(_string).cast<String>().toSet(),
      16 => DateTime.fromMillisecondsSinceEpoch(_intFrom(_double())),
      18 => _dateTimeWithZone(),
      19 => _list(value).toSet(),
      20 => Duration(microseconds: _intFrom(_double())),
      _ => throw FormatException('Unsupported Hive value type $type'),
    };
  }

  DateTime _dateTimeWithZone() {
    final millis = _intFrom(_double());
    final utc = _byte() > 0;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: utc);
  }

  static int _intFrom(double value) => value.isFinite ? value.toInt() : 0;
}
