import 'dart:convert';
import 'dart:math';

import 'package:live_cli/src/danmaku/recorder.dart';
import 'package:live_cli/src/danmaku/scrub_acfun.dart';
import 'package:live_cli/src/danmaku/scrub_sites.dart';
import 'package:live_cli/src/danmaku/scrub_soop.dart';
import 'package:live_cli/src/danmaku/scrub_yy.dart';
import 'package:live_core/live_core.dart';

/// What [FrameScrubber.scrub] produced.
class ScrubbedCapture {
  /// Creates the result.
  new({required this.frames, required this.handshakes, required this.records, required this.danmakuKeys});

  /// Scrubbed frames.
  final List<CapturedFrame> frames;

  /// Handshake URLs and headers with credentials replaced.
  final List<Map<String, Object?>> handshakes;

  /// What was replaced, without the originals.
  final List<Map<String, String>> records;

  /// The room's danmaku keys with private values replaced.
  final Map<String, String> danmakuKeys;
}

/// Synthetic replacements that keep a value's shape (ADR 0009 rule 4): the
/// same original always maps to the same value within one capture; the
/// originals stay in memory only, for the leak check.
class Pseudonyms {
  /// Creates the table; [seed] only makes tests deterministic.
  new({int? seed}) : _random = Random(seed ?? Random.secure().nextInt(1 << 32));

  final Random _random;
  final Map<String, String> _values = {};
  final Set<String> _originals = {};
  var _viewers = 0;

  /// Every value replaced so far.
  Set<String> get originals => _originals;

  static final _cjk = RegExp(r'[^\x00-\x7F]');

  static final _mask = RegExp(r'\*{2,}|＊{2,}');

  /// A viewer's display name: `观众N` when it has non-ASCII characters,
  /// else the same shape. A name the platform masked (`尘***`) keeps its
  /// mask, so masking stays testable.
  String person(String original) {
    if (original.trim().isEmpty) return original;
    return _values.putIfAbsent(original, () {
      _originals.add(original);
      final mask = _mask.firstMatch(original);
      if (mask != null) return '${_cjk.hasMatch(original.substring(0, mask.start)) ? '观' : 'V'}${mask.group(0)}';
      if (_cjk.hasMatch(original)) return '观众${++_viewers}';
      return _shape(original);
    });
  }

  /// A numeric id: the same number of digits; 0 and empty stay.
  String digits(String original) {
    if (original.isEmpty || original == '0' || original.startsWith('-')) return original;
    return _values.putIfAbsent(original, () {
      _originals.add(original);
      final first = 1 + _random.nextInt(8);
      return '$first${[for (var i = 1; i < original.length; i++) _random.nextInt(10)].join()}';
    });
  }

  /// A secret or other private string: same length, digits stay digits,
  /// letters keep their case, other characters stay.
  String secret(String original) {
    if (original.isEmpty) return original;
    return _values.putIfAbsent(original, () {
      _originals.add(original);
      return _shape(original);
    });
  }

  /// Chat text for platforms whose spec asks to replace it (Kuaishou):
  /// same length and character classes.
  String text(String original) {
    if (original.isEmpty) return original;
    return _values.putIfAbsent(original, () {
      _originals.add(original);
      const han = '好的来看这是一个直播主播哈哈加油';
      return String.fromCharCodes([
        for (final rune in original.runes)
          if (rune >= 0x4E00 && rune <= 0x9FFF)
            han.codeUnitAt(_random.nextInt(han.length))
          else if (_isLetterOrDigit(rune))
            _shapeRune(rune)
          else
            rune,
      ]);
    });
  }

  /// The replacement already chosen for [original], if any.
  String? replacementOf(String original) => _values[original];

  /// Every (original, replacement) pair, longest original first.
  List<MapEntry<String, String>> get pairs =>
      _values.entries.toList()..sort((a, b) => b.key.length.compareTo(a.key.length));

  String _shape(String original) => String.fromCharCodes([for (final rune in original.runes) _shapeRune(rune)]);

  static bool _isLetterOrDigit(int rune) =>
      (rune >= 0x30 && rune <= 0x39) || (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);

  int _shapeRune(int rune) {
    if (rune >= 0x30 && rune <= 0x39) return 0x30 + _random.nextInt(10);
    if (rune >= 0x41 && rune <= 0x5A) return 0x41 + _random.nextInt(26);
    if (rune >= 0x61 && rune <= 0x7A) return 0x61 + _random.nextInt(26);
    if (rune > 0x7F) return 0x4E00 + _random.nextInt(0x100);
    return rune;
  }
}

/// Replaces credentials and viewer identities in captured frames
/// (docs/adr/0009-fixture-format.md rules 3 and 4): frames are decoded,
/// scrubbed and encoded again, so the fixtures still decode with the real
/// protocol code.
abstract class FrameScrubber {
  /// Creates the scrubber for [detail]'s room.
  new(this.detail, {int? seed}) : names = Pseudonyms(seed: seed);

  /// The scrubber for [platform].
  factory forPlatform(String platform, RoomDetail detail, {int? seed}) => switch (platform) {
    'acfun' => AcfunFrameScrubber(detail, seed: seed),
    'douyu' => DouyuFrameScrubber(detail, seed: seed),
    'huya' => HuyaFrameScrubber(detail, seed: seed),
    'bilibili' => BilibiliFrameScrubber(detail, seed: seed),
    'douyin' => DouyinFrameScrubber(detail, seed: seed),
    'kuaishou' => KuaishouFrameScrubber(detail, seed: seed),
    'soop' => SoopFrameScrubber(detail, seed: seed),
    'yy' => YyFrameScrubber(detail, seed: seed),
    _ => throw ArgumentError.value(platform, 'platform', 'no frame scrubber'),
  };

  /// The room.
  final RoomDetail detail;

  /// Replacement table.
  final Pseudonyms names;

  /// Records of what was replaced (`where`, `rule`), deduplicated.
  final Set<String> _records = {};

  /// Notes that [where] was scrubbed with [rule].
  void record(String where, String rule) => _records.add('$where\u0000$rule');

  /// Scrubs one frame's bytes; null drops the frame.
  List<int>? scrubFrame(CapturedFrame frame);

  /// The plain content of [frame] (decompressed) for the leak check.
  List<int> plain(CapturedFrame frame) => frame.bytes;

  /// Danmaku keys to publish (private values replaced).
  Map<String, String> scrubKeys(Map<String, String> keys) => keys;

  /// A handshake URL with credentials replaced.
  Uri scrubUrl(Uri url) => url;

  /// Scrubs [frames] and [handshakes].
  ScrubbedCapture scrub(List<CapturedFrame> frames, List<({Uri url, Map<String, String> headers})> handshakes) {
    final keys = scrubKeys(detail.danmakuKeys);
    final out = <CapturedFrame>[];
    for (final frame in frames) {
      final bytes = scrubFrame(frame);
      if (bytes == null) {
        record('frame', 'dropped');
        continue;
      }
      out.add(
        CapturedFrame(
          direction: frame.direction,
          millis: frame.millis,
          bytes: bytes,
          text: frame.text,
          url: frame.url == null ? null : scrubUrl(frame.url!),
        ),
      );
    }
    final shakes = [
      for (final handshake in handshakes)
        {
          'url': scrubUrl(handshake.url).toString(),
          'headers': {
            for (final MapEntry(:key, :value) in handshake.headers.entries)
              key: key.toLowerCase() == 'cookie' ? '<redacted>' : value,
          },
        },
    ];
    if (handshakes.any((handshake) => handshake.headers.keys.any((key) => key.toLowerCase() == 'cookie'))) {
      record('handshake.cookie', 'secret');
    }
    return ScrubbedCapture(
      frames: out,
      handshakes: shakes,
      records: [
        for (final entry in _records) {'where': entry.split('\u0000').first, 'rule': entry.split('\u0000').last},
      ],
      danmakuKeys: keys,
    );
  }

  /// A replaced original (6+ characters) still present in [frames] (their
  /// plain content) or [text], or null.
  String? findLeak(List<CapturedFrame> frames, String text) {
    final haystacks = [text, for (final frame in frames) latin1.decode(plain(frame), allowInvalid: true)];
    for (final original in names.originals) {
      if (original.length < 6) continue;
      final needleText = original;
      final needleBytes = latin1.decode(utf8.encode(original));
      final digits = RegExp(r'^\d+$').hasMatch(original);
      for (final (index, haystack) in haystacks.indexed) {
        final needle = index == 0 ? needleText : needleBytes;
        final found = digits
            ? RegExp('(?<![0-9])${RegExp.escape(needle)}(?![0-9])').hasMatch(haystack)
            : haystack.contains(needle);
        if (found) return '${original.substring(0, 2)}… (${original.length} chars)';
      }
    }
    return null;
  }
}
