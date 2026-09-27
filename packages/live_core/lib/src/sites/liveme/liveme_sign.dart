import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The LiveMe web request signature (spec/sites/liveme.md §6.1): md5 over the
/// sorted query and form pairs, the client id, the timestamp and the web
/// secret. The constants ship in the official web bundle; they identify the
/// web client, not an account.
final class LiveMeSigner {
  /// Creates a signer; [random] is injectable for tests.
  new({Random? random}) : _random = random ?? Random.secure();

  /// `lm_s_id`.
  static const clientId = 'LM6000101139961122666757';
  static const _secret = 'dd46dbb442b6e4ba817d6347d2ddf493';
  static const _valiAlphabet = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

  final Random _random;
  var _counter = 0;

  /// The form with the `lm_s_*` fields added, and the `lm-s-sign` header
  /// value. The timestamp is [now] in milliseconds plus a per-signer counter
  /// digit, so two requests in one millisecond differ.
  ({Map<String, String> fields, String signature}) sign({
    required Map<String, String> query,
    required Map<String, String> form,
    required DateTime now,
  }) {
    final timestamp = '${now.millisecondsSinceEpoch}${_counter++ % 10}';
    return signAt(query: query, form: form, timestamp: timestamp);
  }

  /// [sign] with a fixed [timestamp] (test vectors).
  static ({Map<String, String> fields, String signature}) signAt({
    required Map<String, String> query,
    required Map<String, String> form,
    required String timestamp,
  }) {
    final fields = {
      ...form,
      'lm_s_id': clientId,
      'lm_s_ts': timestamp,
      'lm_s_str': md5.convert(utf8.encode(timestamp)).toString(),
      'lm_s_ver': '1',
      'h5': '1',
    };
    final all = {...query, ...fields};
    final keys = all.keys.toList()..sort();
    final input = StringBuffer();
    for (final key in keys) {
      input
        ..write(key)
        ..write(all[key]);
    }
    input
      ..write(clientId)
      ..write(timestamp)
      ..write(_secret);
    return (fields: fields, signature: md5.convert(utf8.encode(input.toString())).toString());
  }

  /// The `vali` form value: 4 + `l` + 4 + `m` + 5 characters of the web
  /// alphabet.
  String vali() {
    String part(int length) =>
        List.generate(length, (_) => _valiAlphabet[_random.nextInt(_valiAlphabet.length)]).join();
    return '${part(4)}l${part(4)}m${part(5)}';
  }
}
