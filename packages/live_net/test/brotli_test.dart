import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_net/live_net.dart';
import 'package:live_net/src/codec/brotli_dictionary.dart';
import 'package:live_net/src/codec/brotli_tables.dart';
import 'package:test/test.dart';

import 'support/digests.dart';

// Vectors written by tools/brotli/gen_test_vectors.py with the reference
// implementation (docs/Q-网络和代理/Q01-请求和编码/Q01.2-Brotli解码/record.md).
const _data = 'test/data/brotli';

/// Streams of one vector group with the reference decoder's verdict:
/// `'error'`, or the output's `length` and `sha256`.
typedef _Vector = ({String name, Uint8List stream, Object? expect});

List<_Vector> _load(String group) {
  final bin = File('$_data/$group.bin').readAsBytesSync();
  final manifest = jsonDecode(File('$_data/$group.json').readAsStringSync()) as Map<String, Object?>;
  return [
    for (final entry in (manifest['vectors']! as List<Object?>).cast<Map<String, Object?>>())
      (
        name: '$group/${entry['name']}',
        stream: Uint8List.sublistView(
          bin,
          entry['offset']! as int,
          (entry['offset']! as int) + (entry['size']! as int),
        ),
        expect: entry['expect'],
      ),
  ];
}

/// Decodes [stream] and says how the result differs from [expect], or null.
String? _check(Uint8List stream, Object? expect, {int? maxOutput}) {
  final Uint8List output;
  try {
    output = brotliDecode(stream, maxOutput: maxOutput);
  } on FormatException catch (error) {
    return expect == 'error' ? null : 'rejected: ${error.message}';
  } on Object catch (error) {
    return 'threw ${error.runtimeType}: $error';
  }
  if (expect == 'error') return 'accepted (${output.length} bytes); the reference decoder rejects it';
  final expected = expect! as Map<String, Object?>;
  if (output.length != expected['length']) return 'decoded ${output.length} bytes, expected ${expected['length']}';
  if (sha256Hex(output) != expected['sha256']) return 'decoded bytes differ';
  return null;
}

void main() {
  group('tables', () {
    test('digest helpers', () {
      expect(sha256Hex(const []), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(sha256Hex(utf8.encode('abc')), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(
        sha256Hex(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
      expect(crc32(utf8.encode('123456789')), 0xcbf43926);
    });

    test('static dictionary: size and CRC-32 of RFC 7932, SHA-256 of the reference implementation', () {
      expect(brotliDictionary, hasLength(122784));
      expect(crc32(brotliDictionary), 0x5136cb04);
      // Same in RFC 7932 Appendix A, libbrotlicommon 1.2.0 and google/brotli's c/common/dictionary.bin.
      expect(sha256Hex(brotliDictionary), '20e42eb1b511c21806d4d227d07e5dd06877d8ce7b3a817f378f313653f35c70');
      expect(brotliDictionaryOffsets[25], brotliDictionary.length);
    });

    test('context lookup tables: CRC-32 of RFC 7932 section 7.1', () {
      expect(crc32(brotliLut0), 0x8e91efb7);
      expect(crc32(brotliLut1), 0xd01a32f4);
      expect(crc32(brotliLut2), 0x0dd7a0d6);
    });

    test('transforms: length and CRC-32 of RFC 7932 Appendix B', () {
      final bytes = <int>[];
      for (final (prefix, type, suffix) in brotliTransforms) {
        bytes
          ..addAll(utf8.encode(prefix))
          ..add(0)
          ..add(type)
          ..addAll(utf8.encode(suffix))
          ..add(0);
      }
      expect(brotliTransforms, hasLength(121));
      expect(bytes, hasLength(648));
      expect(crc32(bytes), 0x3d965f81);
    });

    test('every transform of every dictionary word matches libbrotlicommon', () {
      final manifest = jsonDecode(File('$_data/transforms.json').readAsStringSync()) as Map<String, Object?>;
      final expected = (manifest['sha256']! as Map<String, Object?>).cast<String, String>();
      final word = Uint8List(40);
      var wrongLengths = 0;
      for (var length = 4; length <= 24; length++) {
        final all = BytesBuilder(copy: false);
        for (var index = 0; index < 1 << brotliDictionaryBits[length]; index++) {
          final offset = brotliDictionaryOffsets[length] + index * length;
          for (var transform = 0; transform < 121; transform++) {
            final end = brotliTransformWord(word, 0, brotliDictionary, offset, length, transform);
            if (end != brotliTransformedLength(length, transform)) wrongLengths++;
            all.add(word.sublist(0, end));
          }
        }
        expect(sha256Hex(all.takeBytes()), expected['$length'], reason: 'words of length $length');
      }
      expect(wrongLengths, 0);
    });
  });

  group('same output as the reference decoder', () {
    for (final (group, count) in [('official', 41), ('reference', 236), ('crafted', 254)]) {
      test(group, () {
        final vectors = _load(group);
        expect(vectors, hasLength(count));
        final failures = [
          for (final vector in vectors)
            if (_check(vector.stream, vector.expect) case final problem?) '${vector.name}: $problem',
        ];
        expect(failures, isEmpty);
      });
    }

    test('the crafted streams reach every feature', () {
      final names = _load('crafted').map((vector) => vector.name).toSet();
      for (final feature in ['lsb6', 'msb6', 'utf8', 'signed']) {
        expect(names, contains('crafted/context/$feature-0'));
      }
      for (var transform = 0; transform < 121; transform++) {
        expect(names, contains('crafted/transform/$transform'));
      }
      for (var window = 10; window <= 24; window++) {
        expect(names, contains('crafted/window/w$window'));
      }
    });

    test('streams past 16 MiB, with a repeat just inside and just outside the window', () {
      for (final vector in _load('reference').where((vector) => vector.name.contains('16m-'))) {
        final output = brotliDecode(vector.stream);
        expect(output.length, greaterThan(1 << 24));
        expect(_check(vector.stream, vector.expect), isNull, reason: vector.name);
      }
    });
  });

  group('interface', () {
    test('the empty stream and a plain list', () {
      expect(brotliDecode(const [0x06]), isEmpty);
      final quickfox = _load('official').firstWhere((vector) => vector.name == 'official/quickfox.compressed');
      expect(utf8.decode(brotliDecode(quickfox.stream.toList())), 'The quick brown fox jumps over the lazy dog');
    });

    test('maxOutput: the exact size passes, one byte less is rejected', () {
      final alice = _load('official').firstWhere((vector) => vector.name == 'official/alice29.txt.compressed');
      expect(brotliDecode(alice.stream, maxOutput: 152089), hasLength(152089));
      expect(
        () => brotliDecode(alice.stream, maxOutput: 152088),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('limit of 152088 bytes'))),
      );
      expect(() => brotliDecode(alice.stream, maxOutput: -1), throwsArgumentError);
    });

    test('maxOutput stops a decompression bomb at the first meta-block header', () {
      // Each meta-block is 13 bytes that decode to 16 MiB of zeros.
      final small = _bomb(metablocks: 3, length: 1 << 20);
      final output = brotliDecode(small);
      expect(output, hasLength(3 << 20));
      expect(output.every((byte) => byte == 0), isTrue);
      final bomb = _bomb(metablocks: 64, length: 1 << 24);
      expect(bomb.length, lessThan(1024));
      final watch = Stopwatch()..start();
      expect(() => brotliDecode(bomb, maxOutput: 1 << 20), throwsFormatException);
      expect(() => brotliDecode(bomb, maxOutput: (1 << 24) + 5), throwsFormatException);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('a large-window stream (not RFC 7932) is rejected', () {
      final quickfox = _load('official').firstWhere((vector) => vector.name == 'official/quickfox.compressed');
      expect(
        () => brotliDecode(_rewindow(quickfox.stream, '0010001')),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('large-window'))),
      );
    });
  });

  group('bad input', () {
    test("damaged streams get the reference decoder's verdict, within the time limit", () async {
      final result = await Isolate.run(_runMutations).timeout(const Duration(minutes: 2));
      expect(result.count, greaterThan(2000));
      expect(result.failures, isEmpty);
      expect(result.slowest, lessThan(const Duration(seconds: 1)));
    });

    test('every truncation is a FormatException', () async {
      final result = await Isolate.run(_runTruncations).timeout(const Duration(minutes: 2));
      expect(result.count, greaterThan(70000));
      expect(result.failures, isEmpty);
      expect(result.slowest, lessThan(const Duration(seconds: 1)));
    });

    test('random bytes and flipped bits: decoded or a FormatException, within the time limit', () async {
      final result = await Isolate.run(_runFuzz).timeout(const Duration(minutes: 2));
      expect(result.count, greaterThan(5000));
      expect(result.failures, isEmpty);
      expect(result.slowest, lessThan(const Duration(seconds: 1)));
    });
  });

  test('Missevan danmaku frames decode to JSON', () {
    // fixtures/missevan/danmaku/S06-live: frame = 1 (Brotli), 3-byte little-endian length, stream.
    final lines = File('../../fixtures/missevan/danmaku/S06-live/frames.jsonl').readAsLinesSync();
    final messages = <Map<String, Object?>>[];
    for (final line in lines) {
      final frame = jsonDecode(line) as Map<String, Object?>;
      final encoded = frame['b64'];
      if (frame['dir'] != 'in' || encoded is! String) continue;
      final bytes = base64Decode(encoded);
      expect(bytes[0], 1);
      final length = bytes[1] | bytes[2] << 8 | bytes[3] << 16;
      final decoded = brotliDecode(Uint8List.sublistView(bytes, 4), maxOutput: length);
      expect(decoded, hasLength(length));
      messages.add(jsonDecode(utf8.decode(decoded)) as Map<String, Object?>);
    }
    expect(messages, hasLength(10));
    expect(messages.first, {
      'type': 'user',
      'event': 'connect',
      'user': {'user_id': 0},
    });
    expect(messages.map((message) => message['type'] ?? message['event']), contains('message'));
  });
}

typedef _Run = ({int count, List<String> failures, Duration slowest});

/// Replays mutations.json: every case must get the reference decoder's
/// verdict.
_Run _runMutations() {
  final streams = {
    for (final group in ['official', 'reference', 'crafted'])
      for (final vector in _load(group)) vector.name: vector.stream,
  };
  final manifest = jsonDecode(File('$_data/mutations.json').readAsStringSync()) as Map<String, Object?>;
  final cases = (manifest['cases']! as List<Object?>).cast<Map<String, Object?>>();
  final failures = <String>[];
  var slowest = Duration.zero;
  for (final entry in cases) {
    final base = streams[entry['base']]!;
    final Uint8List input;
    if (entry['truncate'] case final int length) {
      input = Uint8List.sublistView(base, 0, length);
    } else if (entry['flip'] case final List<Object?> bits) {
      input = Uint8List.fromList(base);
      for (final bit in bits.cast<int>()) {
        input[bit >> 3] ^= 1 << (bit & 7);
      }
    } else if (entry['append'] case final String hex) {
      input = Uint8List.fromList([
        ...base,
        for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
    } else {
      input = _rewindow(base, entry['window']! as String);
    }
    final watch = Stopwatch()..start();
    final problem = _check(input, entry['expect']);
    if (watch.elapsed > slowest) slowest = watch.elapsed;
    if (problem != null) failures.add('${jsonEncode({...entry}..remove('expect'))}: $problem');
  }
  return (count: cases.length, failures: failures, slowest: slowest);
}

/// Proper prefixes of the valid streams of up to 1 MiB of output: all of them
/// for streams up to 1 KiB, 50 for longer ones; each is truncated.
_Run _runTruncations() {
  final random = Random(16);
  final failures = <String>[];
  var count = 0;
  var slowest = Duration.zero;
  for (final group in ['official', 'reference', 'crafted']) {
    for (final vector in _load(group)) {
      final size = vector.stream.length;
      final expect = vector.expect;
      if (expect is! Map<String, Object?> || (expect['length']! as int) > 1 << 20) continue;
      final cuts = size <= 1024
          ? [for (var i = 0; i < size; i++) i]
          : [for (var i = 0; i < 50; i++) random.nextInt(size)];
      for (final length in cuts) {
        count++;
        final watch = Stopwatch()..start();
        final problem = _check(Uint8List.sublistView(vector.stream, 0, length), 'error');
        if (watch.elapsed > slowest) slowest = watch.elapsed;
        if (problem != null) failures.add('${vector.name} cut at $length: $problem');
      }
    }
  }
  return (count: count, failures: failures, slowest: slowest);
}

/// Random bytes, and random bits flipped in larger streams than the ones in
/// mutations.json: either output or a FormatException, never another error.
_Run _runFuzz() {
  final random = Random(7932);
  final failures = <String>[];
  var count = 0;
  var slowest = Duration.zero;
  void run(String label, Uint8List input) {
    count++;
    final watch = Stopwatch()..start();
    try {
      brotliDecode(input, maxOutput: 1 << 22);
    } on FormatException {
      // Expected for most inputs.
    } on Object catch (error) {
      failures.add('$label: threw ${error.runtimeType}: $error');
    }
    if (watch.elapsed > slowest) slowest = watch.elapsed;
  }

  for (var i = 0; i < 4000; i++) {
    final length = random.nextInt(i < 2000 ? 16 : 800);
    run('random #$i', Uint8List.fromList([for (var j = 0; j < length; j++) random.nextInt(256)]));
  }
  final large = [
    for (final group in ['official', 'reference', 'crafted'])
      for (final vector in _load(group))
        if (vector.expect != 'error' && vector.stream.length > 4096 && vector.stream.length < 200000) vector,
  ];
  for (var i = 0; i < 1500; i++) {
    final vector = large[random.nextInt(large.length)];
    final input = Uint8List.fromList(vector.stream);
    final flips = 1 + random.nextInt(3);
    for (var j = 0; j < flips; j++) {
      final bit = random.nextInt(input.length * 8);
      input[bit >> 3] ^= 1 << (bit & 7);
    }
    run('${vector.name} flipped #$i', input);
  }
  return (count: count, failures: failures, slowest: slowest);
}

/// [stream] with its window size field replaced by [pattern], written as in
/// RFC 7932 section 9.1 (read right to left).
Uint8List _rewindow(Uint8List stream, String pattern) {
  final first = stream[0];
  final drop = first & 1 == 0 ? 1 : ((first >> 1) & 7 != 0 ? 4 : 7);
  final bits = [
    for (final char in pattern.split('').reversed) int.parse(char),
    for (var i = drop; i < stream.length * 8; i++) stream[i >> 3] >> (i & 7) & 1,
  ];
  final bytes = Uint8List((bits.length + 7) >> 3);
  for (var i = 0; i < bits.length; i++) {
    bytes[i >> 3] |= bits[i] << (i & 7);
  }
  return bytes;
}

/// [metablocks] meta-blocks of [length] zeros each (at most 2^24), from one
/// command whose single literal takes no bits: about 13 bytes each.
Uint8List _bomb({required int metablocks, required int length}) {
  final bits = _BitWriter()..write(0, 1); // WBITS 16
  final nibbles = max(4, ((length - 1).bitLength + 3) >> 2);
  for (var i = 0; i < metablocks; i++) {
    bits
      ..write(0, 1) // ISLAST
      ..write(nibbles - 4, 2)
      ..write(length - 1, 4 * nibbles)
      ..write(0, 1) // ISUNCOMPRESSED
      ..write(0, 3) // one block type each
      ..write(0, 6) // NPOSTFIX, NDIRECT
      ..write(0, 2) // context mode LSB6
      ..write(0, 2) // one literal and one distance prefix code
      ..write(1, 2) // literals: simple code, one symbol: 0
      ..write(0, 2)
      ..write(0, 8)
      ..write(1, 2) // commands: simple code, one symbol: insert code 23, copy code 0
      ..write(0, 2)
      ..write(7 * 64 + 7 * 8, 10)
      ..write(1, 2) // distances: simple code, one symbol
      ..write(0, 2)
      ..write(0, 6)
      ..write(length - 22594, 24); // insert length = 22594 + extra bits
  }
  return (bits
        ..write(1, 1) // ISLAST
        ..write(1, 1)) // ISLASTEMPTY
      .bytes();
}

final class _BitWriter {
  final List<int> _bytes = [];
  int _buffer = 0;
  int _count = 0;

  void write(int value, int count) {
    _buffer |= value << _count;
    _count += count;
    while (_count >= 8) {
      _bytes.add(_buffer & 0xff);
      _buffer >>= 8;
      _count -= 8;
    }
  }

  Uint8List bytes() => Uint8List.fromList([..._bytes, if (_count > 0) _buffer]);
}
