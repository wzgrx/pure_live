import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/text.dart';
import 'package:meta/meta.dart';

/// The encryption descriptor from `getEncryption` (spec/sites/douyu.md §6.1).
@immutable
final class DouyuDescriptor {
  /// Creates a descriptor.
  const new({
    required this.key,
    required this.randStr,
    required this.encData,
    required this.encTime,
    required this.expireAt,
    required this.isSpecial,
  });

  /// Parses `getEncryption`; a missing or out-of-range field is ApiChanged.
  factory parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const ApiChanged('douyu', 'getEncryption: not JSON');
    }
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) throw const ApiChanged('douyu', 'getEncryption: no data');
    final key = jsonString(data['key']);
    final randStr = jsonString(data['rand_str']);
    final encData = jsonString(data['enc_data']);
    final encTime = jsonInt(data['enc_time']);
    final expireAt = jsonInt(data['expire_at']);
    if (key == null || randStr == null || encData == null || encTime == null || expireAt == null) {
      throw const ApiChanged('douyu', 'getEncryption: missing field');
    }
    if (encTime < 1 || encTime > 16) throw ApiChanged('douyu', 'getEncryption: enc_time $encTime');
    return DouyuDescriptor(
      key: key,
      randStr: randStr,
      encData: encData,
      encTime: encTime,
      expireAt: DateTime.fromMillisecondsSinceEpoch(expireAt * 1000, isUtc: true),
      isSpecial: jsonInt(data['is_special']) == 1,
    );
  }

  /// Signing key.
  final String key;

  /// Initial secret.
  final String randStr;

  /// Passed through to the play form.
  final String encData;

  /// Number of hashing rounds (1..16).
  final int encTime;

  /// When the descriptor stops working.
  final DateTime expireAt;

  /// Special rooms sign without the room id and time.
  final bool isSpecial;

  /// Usable when it expires more than 30 s after [now].
  bool usableAt(DateTime now) => expireAt.isAfter(now.add(const Duration(seconds: 30)));

  /// §6.2 `auth` for room [rid] at Unix seconds [tt].
  String auth(String rid, int tt) {
    var secret = randStr;
    for (var round = 0; round < encTime; round++) {
      secret = md5.convert(utf8.encode('$secret$key')).toString();
    }
    final salt = isSpecial ? '' : '$rid$tt';
    return md5.convert(utf8.encode('$secret$key$salt')).toString();
  }
}
