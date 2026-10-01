import 'package:path/path.dart' as p;
import 'package:pinyindart/pinyindart.dart';

final _invalidComponentChars = RegExp(r'[\x00-\x1F<>:"/\\|?*]');
final _windowsReservedName = RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$', caseSensitive: false);

/// One portable path component from an untrusted label (3.x
/// `PathHelper.toSafeComponent`): separators and reserved characters become
/// `_`, trailing dots and spaces go, Windows device names get a `_` prefix,
/// at most [maxRunes] characters; empty results are `unknown`.
String safePathComponent(String text, {bool asciiOnly = false, int maxRunes = 80}) {
  if (maxRunes < 1) return 'unknown';
  var value = text.trim().replaceAll(_invalidComponentChars, '_').replaceAll(RegExp(r'\s+'), '_');
  if (asciiOnly) value = value.replaceAll(RegExp('[^a-zA-Z0-9_]'), '');
  value = value.replaceAll(RegExp('_+'), '_').replaceAll(RegExp(r'[. ]+$'), '');
  if (value.isEmpty || value.replaceAll('_', '').isEmpty || value == '.' || value == '..') return 'unknown';
  final runes = value.runes.toList(growable: false);
  if (runes.length > maxRunes) value = String.fromCharCodes(runes.take(maxRunes));
  if (_windowsReservedName.hasMatch(value)) value = '_$value';
  return value;
}

/// [text] in toneless pinyin as a lower-case ASCII component (3.x
/// `PathHelper.toSafePinyin`).
String safePinyinComponent(String text) {
  if (text.trim().isEmpty) return 'unknown';
  return safePathComponent(getPinyin(text, withTone: false, separator: ''), asciiOnly: true).toLowerCase();
}

/// The directory of one attempt below the recording root (3.x
/// `CacheService.getRoomDir`): `<platform>/<streamer>/<yyyy-MM-dd>/<HH-mm-ss>`.
String attemptDirectory(
  String root, {
  required String platform,
  required String nick,
  required DateTime now,
  bool pinyin = false,
}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final date = '${now.year}-${two(now.month)}-${two(now.day)}';
  final time = '${two(now.hour)}-${two(now.minute)}-${two(now.second)}';
  final component = pinyin ? safePinyinComponent : safePathComponent;
  return p.join(root, component(platform), component(nick), date, time);
}
