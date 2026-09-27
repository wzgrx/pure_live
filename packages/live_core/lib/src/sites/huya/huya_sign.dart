import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:live_core/src/sites/huya/huya_parse.dart';
import 'package:meta/meta.dart';

/// Why a Huya AntiCode could not be signed (spec/sites/huya.md §6.4).
enum HuyaSignFailureKind {
  /// No valid `wsTime`, an `fm` that does not decode, or a template without
  /// all of `$0`–`$3` (REG-HUYA-005).
  malformed,

  /// `wsTime + 300 s` has passed. The credential must be fetched again; it is
  /// never extended locally (REG-HUYA-004).
  expired,
}

/// An AntiCode that cannot be signed. The message never carries token
/// material (§6.7).
@immutable
final class HuyaSignFailure implements Exception {
  /// Creates the failure.
  const new(this.kind, this.reason);

  /// What went wrong.
  final HuyaSignFailureKind kind;

  /// Diagnostic reason without secrets.
  final String reason;

  @override
  String toString() => 'HuyaSignFailure(${kind.name}: $reason)';
}

/// The milliseconds used for `seqid`: never less than the wall clock and
/// strictly increasing, so a player and a recorder opening the same line in
/// the same millisecond still get different `seqid` and `wsSecret`
/// (§6.4 step 4, REG-HUYA-007).
final class HuyaSignClock {
  /// Creates a clock; adapters share [process] unless a test injects one.
  new();

  /// The clock shared by every Huya adapter in this process.
  static final HuyaSignClock process = HuyaSignClock();

  int _last = 0;

  /// The next signing millisecond for the wall time [now].
  int next(DateTime now) {
    final wall = now.millisecondsSinceEpoch;
    return _last = wall > _last ? wall : _last + 1;
  }
}

/// Huya AntiCode signing and viewer identity helpers (spec/sites/huya.md
/// §6.4, §8), ported from the legacy `HuyaSite.buildAntiCode`
/// (lib/core/site/huya/huya_site.dart:1062-1141).
abstract final class HuyaSign {
  static const _placeholders = [r'$0', r'$1', r'$2', r'$3'];

  /// Server parameters the signed query replaces or drops (§6.4 step 9).
  static const _dropped = {'wsSecret', 'seqid', 'u', 'uid', 'uuid', 'fm'};

  /// A `%` that does not start an escape (`Uri.decodeComponent` would throw).
  static final _badEscape = RegExp('%(?![0-9A-Fa-f]{2})');

  /// Whether [antiCode] carries an `fm` template that must be signed.
  static bool hasTemplate(String antiCode) =>
      _parse(antiCode).any((param) => param.key == 'fm' && param.value.trim().isNotEmpty);

  /// Signs [antiCode] for [streamName] as [uid] (§6.4). A query without an
  /// `fm` template is returned unchanged (already signed, or a legacy static
  /// token). Parameters the signer does not own keep their original spelling
  /// and position.
  ///
  /// - `seqid = uid + clock.next(now)`, `hash = md5("seqid|ctype|t")`;
  ///   `ctype` defaults to `huya_webh5`, `t` to `100`; `t=103` is WAP.
  /// - `wsSecret = md5(template)` with the first `$0` replaced by the rotated
  ///   UID (the UID itself for WAP), `$1` by the stream, `$2` by the hash and
  ///   `$3` by `wsTime` as the server wrote it.
  /// - Output: `wsSecret seqid u uid uuid fm` removed, then `wsSecret`,
  ///   `wsTime`, `seqid`, `ctype`, `ver=1`, `fs` (default `bgct`), `t`, and
  ///   `u` (or WAP `uid` and a random `uuid`) set in that order: an existing
  ///   key is replaced in place, a missing one appended.
  ///
  /// Throws [HuyaSignFailure]: `malformed` without a hexadecimal `wsTime`, an
  /// `fm` that does not decode, or a template missing a placeholder;
  /// `expired` when the signing time is past `wsTime + 300 s`.
  static String sign(
    String antiCode, {
    required String streamName,
    required int uid,
    required HuyaSignClock clock,
    required DateTime now,
    Random? random,
  }) {
    final params = _parse(antiCode);
    String? value(String key) {
      for (final param in params) {
        if (param.key != key) continue;
        try {
          if (_badEscape.hasMatch(param.value)) throw const FormatException();
          return Uri.decodeComponent(param.value).trim();
        } on FormatException {
          throw HuyaSignFailure(HuyaSignFailureKind.malformed, '$key is not percent-encoded UTF-8');
        }
      }
      return null;
    }

    String orDefault(String? value, String fallback) => value == null || value.isEmpty ? fallback : value;

    final fm = value('fm') ?? '';
    if (fm.isEmpty) return antiCode;
    if (uid <= 0) throw const HuyaSignFailure(HuyaSignFailureKind.malformed, 'no signing UID');

    final ctype = orDefault(value('ctype'), 'huya_webh5');
    final platform = orDefault(value('t'), '100');
    final wap = platform == '103';
    final wsTime = value('wsTime') ?? '';
    final wsSeconds = int.tryParse(wsTime, radix: 16);
    if (wsSeconds == null || wsSeconds <= 0 || !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(wsTime)) {
      throw const HuyaSignFailure(HuyaSignFailureKind.malformed, 'no hexadecimal wsTime');
    }

    final String template;
    try {
      template = utf8.decode(base64.decode(base64.normalize(fm)));
    } on FormatException {
      throw const HuyaSignFailure(HuyaSignFailureKind.malformed, 'fm is not base64 UTF-8');
    }
    if (!_placeholders.every(template.contains)) {
      throw const HuyaSignFailure(HuyaSignFailureKind.malformed, r'fm template lacks $0-$3');
    }

    final millis = clock.next(now);
    if (millis ~/ 1000 > wsSeconds + 300) {
      throw const HuyaSignFailure(HuyaSignFailureKind.expired, 'wsTime + 300 s has passed');
    }
    final seqId = uid + millis;
    final hash = md5.convert(utf8.encode('$seqId|$ctype|$platform')).toString();
    final rotated = HuyaParse.rotateUid(uid);
    final secret = template
        .replaceFirst(r'$0', '${wap ? uid : rotated}')
        .replaceFirst(r'$1', streamName)
        .replaceFirst(r'$2', hash)
        .replaceFirst(r'$3', wsTime);
    final wsSecret = md5.convert(utf8.encode(secret)).toString();

    final output = [
      for (final param in params)
        if (!_dropped.contains(param.key)) (key: param.key, raw: param.raw),
    ];
    void put(String key, String value) {
      final segment = (key: key, raw: '$key=${Uri.encodeQueryComponent(value)}');
      final index = output.indexWhere((param) => param.key == key);
      if (index < 0) {
        output.add(segment);
      } else {
        output[index] = segment;
      }
    }

    put('wsSecret', wsSecret);
    put('wsTime', wsTime);
    put('seqid', '$seqId');
    put('ctype', ctype);
    put('ver', '1');
    put('fs', value('fs') ?? 'bgct');
    put('t', platform);
    if (wap) {
      final rng = random ?? Random();
      final ct = ((wsSeconds + rng.nextDouble()) * 1000).toInt();
      final uuid = (((ct % 1e10) + rng.nextDouble()) * 1e3 % 0xffffffff).toInt();
      put('uid', '$uid');
      put('uuid', '$uuid');
    } else {
      put('u', '$rotated');
    }
    return output.map((param) => param.raw).join('&');
  }

  /// The query split without decoding; the first value of a repeated key
  /// wins and later ones are dropped.
  static List<({String key, String value, String raw})> _parse(String query) {
    final params = <({String key, String value, String raw})>[];
    final seen = <String>{};
    for (final segment in query.trim().split('&')) {
      if (segment.isEmpty) continue;
      final separator = segment.indexOf('=');
      final key = separator < 0 ? segment : segment.substring(0, separator);
      if (!seen.add(key)) continue;
      params.add((key: key, value: separator < 0 ? '' : segment.substring(separator + 1), raw: segment));
    }
    return params;
  }

  /// §8 the account UID: an exact `yyuid=<digits>` cookie field above 0
  /// (`foo=yyuid=12` does not count).
  static int? viewerUidFromCookie(String? cookie) {
    if (cookie == null) return null;
    final match = RegExp(r'(?:^|;\s*)yyuid=(\d+)(?:;|$)').firstMatch(cookie.trim());
    final uid = int.tryParse(match?.group(1) ?? '');
    return uid != null && uid > 0 ? uid : null;
  }

  /// §8 a local temporary viewer UID when anonymous login fails:
  /// 1400000000000 plus a uniform value in [0, 10^11), composed from two
  /// ranges `Random.nextInt` supports (REG-HUYA-017).
  static int fallbackViewerUid(Random random) =>
      1400000000000 + random.nextInt(1000000) * 100000 + random.nextInt(100000);

  /// §8 a 32-digit lower-case hexadecimal GUID.
  static String guid(Random random) => List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
}
