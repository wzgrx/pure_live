import 'package:live_iptv/src/model.dart';

/// Matches playlist channels to guide channels (spec/product.md F-IPTV-02,
/// spec/modules/iptv.md §3). Built once per guide; every step only accepts a
/// unique answer (an ambiguous one falls through to the next step), so the
/// result never depends on guide order.
///
/// 1. `tvg-id` equals a guide channel id (case-insensitive).
/// 2. The normalised `tvg-name`, channel name or `tvg-id` equals a guide
///    channel's normalised name or id.
/// 3. Their channel code equals a guide channel's code: `CCTV-1 综合` and
///    `CCTV1` are both `cctv1`; `CCTV-5+` is `cctv5plus`.
/// 4. One normalised name contains the other without splitting an ASCII
///    word or number (`cctv1` never matches `cctv10` or `cctv1plus`).
final class GuideMatcher {
  /// Indexes [channels].
  new(Iterable<IptvGuideChannel> channels) {
    for (final channel in channels) {
      _add(_byId, channel.id.trim().toLowerCase(), channel.id);
      for (final text in {channel.id, ...channel.names}) {
        final key = normalizeChannelName(text);
        if (key.isEmpty) continue;
        _add(_byName, key, channel.id);
        final code = channelCode(key);
        if (code != null) _add(_byCode, code, channel.id);
      }
    }
  }

  final _byId = <String, Set<String>>{};
  final _byName = <String, Set<String>>{};
  final _byCode = <String, Set<String>>{};

  static void _add(Map<String, Set<String>> index, String key, String id) {
    if (key.isNotEmpty) index.putIfAbsent(key, () => {}).add(id);
  }

  static String? _unique(Set<String>? ids) => ids != null && ids.length == 1 ? ids.single : null;

  /// The guide channel id for a playlist channel, or null.
  String? match({required String name, String? tvgId, String? tvgName}) {
    final id = tvgId?.trim().toLowerCase();
    if (id != null && id.isNotEmpty) {
      if (_unique(_byId[id]) case final found?) return found;
    }
    final keys = {
      for (final text in [tvgName, name, tvgId])
        if (text != null) normalizeChannelName(text),
    }.where((key) => key.isNotEmpty).toList();
    for (final key in keys) {
      if (_unique(_byName[key]) case final found?) return found;
    }
    for (final key in keys) {
      final code = channelCode(key);
      if (code == null) continue;
      if (_unique(_byCode[code]) case final found?) return found;
    }
    for (final key in keys) {
      if (key.runes.length < 2) continue;
      final found = <String>{};
      for (final MapEntry(key: other, value: ids) in _byName.entries) {
        if (other.runes.length < 2) continue;
        if (_contains(other, key) || _contains(key, other)) found.addAll(ids);
        if (found.length > 1) break;
      }
      if (_unique(found) case final match?) return match;
    }
    return null;
  }

  /// Whether [outer] contains [inner] without splitting an ASCII word or
  /// number: `cctv1综合` contains `cctv1`, but `cctv10`, `cctv4k` and
  /// `cctv5plus` do not contain `cctv1`, `cctv4`, `cctv5`.
  static bool _contains(String outer, String inner) {
    var from = 0;
    while (true) {
      final at = outer.indexOf(inner, from);
      if (at < 0) return false;
      final end = at + inner.length;
      final before = at > 0 && _ascii(outer.codeUnitAt(at - 1)) && _ascii(inner.codeUnitAt(0));
      final after = end < outer.length && _ascii(outer.codeUnitAt(end)) && _ascii(inner.codeUnitAt(inner.length - 1));
      if (!before && !after) return true;
      from = at + 1;
    }
  }

  static bool _ascii(int unit) => (unit >= 0x30 && unit <= 0x39) || (unit >= 0x61 && unit <= 0x7a);
}

final _brackets = RegExp(r'\([^)]*\)|\[[^\]]*\]|（[^）]*）|【[^】]*】');
final _separators = RegExp(r'[\s\-_.·|/:：]+');
const _qualityTokens = {
  'hd',
  'fhd',
  'uhd',
  'sd',
  'hdr',
  'hevc',
  'h264',
  'h265',
  'avc',
  '1080p',
  '1080i',
  '720p',
  '576p',
  '576i',
  '2160p',
  '50fps',
  '60fps',
  '25fps',
};
final _qualitySuffix = RegExp(r'(?<=[0-9\u3400-\u9fff])(uhd|fhd|hd|sd)$');
final _cjkQuality = RegExp('超高清|高清|超清|标清|蓝光|频道');
final _other = RegExp(r'[^a-z0-9\u3400-\u4dbf\u4e00-\u9fff]');

/// A channel name reduced for matching: full-width letters made ASCII,
/// lower-cased, `+` spelled `plus`, bracketed notes and quality marks (`HD`,
/// `1080P`, `高清`, `频道`) removed, then everything except letters, digits and
/// CJK removed. `CCTV-1 综合 HD` → `cctv1综合`; `湖南卫视 高清` → `湖南卫视`.
String normalizeChannelName(String name) {
  final buffer = StringBuffer();
  for (final rune in name.runes) {
    if (rune >= 0xff01 && rune <= 0xff5e) {
      buffer.writeCharCode(rune - 0xfee0);
    } else if (rune == 0x3000) {
      buffer.write(' ');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  final text = buffer.toString().toLowerCase().replaceAll('+', 'plus').replaceAll(_brackets, ' ');
  final tokens = [
    for (final token in text.split(_separators))
      if (!_qualityTokens.contains(token)) token.replaceAll(_cjkQuality, '').replaceFirst(_qualitySuffix, ''),
  ];
  return tokens.join().replaceAll(_other, '');
}

final _code = RegExp(r'^([a-z]+[0-9]+(?:plus)?)(?:[\u3400-\u4dbf\u4e00-\u9fff].*)?$');

/// The letters-and-number code that starts a normalised name followed only
/// by CJK text (`cctv1综合` → `cctv1`, `cctv5plus` → `cctv5plus`); null when
/// there is none.
String? channelCode(String normalized) => _code.firstMatch(normalized)?.group(1);
