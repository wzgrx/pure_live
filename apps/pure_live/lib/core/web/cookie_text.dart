import 'package:pure_live_app/core/web/web_engine.dart';

final _controls = RegExp('[\u0000-\u001f\u007f]');
final _validName = RegExp(r"^[A-Za-z0-9_!#$%&'*+.^`|~-]+$");

/// A pasted or collected cookie header without control characters, a leading
/// `Cookie:` or outer blanks (spec/sites/bilibili.md §8.2 normalisation).
String normalizeCookie(String cookie) =>
    cookie.replaceAll(_controls, '').trim().replaceFirst(RegExp(r'^Cookie:\s*', caseSensitive: false), '').trim();

/// The `Cookie` header for [cookies] from the browser: `name=value` joined
/// with `; `, invalid names and empty values dropped, the first of a repeated
/// name kept (the most specific path comes first).
String cookieHeader(Iterable<WebCookie> cookies) {
  final seen = <String>{};
  return [
    for (final cookie in cookies)
      if (cookie.name.trim() case final name when _validName.hasMatch(name))
        if (cookie.value.replaceAll(_controls, '').trim() case final value when value.isNotEmpty)
          if (seen.add(name)) '$name=$value',
  ].join('; ');
}

/// The value of field [name] in [cookie] (names match exactly), or null.
String? cookieField(String cookie, String name) {
  for (final part in normalizeCookie(cookie).split(';')) {
    final separator = part.indexOf('=');
    if (separator <= 0 || part.substring(0, separator).trim() != name) continue;
    final value = part.substring(separator + 1).trim();
    return value.isEmpty ? null : value;
  }
  return null;
}
