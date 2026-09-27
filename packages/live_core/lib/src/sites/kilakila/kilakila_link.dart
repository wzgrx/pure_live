import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:live_core/src/aes.dart';
import 'package:meta/meta.dart';

/// What a KilaKila link names (spec/sites/kilakila.md §1).
enum KilakilaLinkKind {
  /// One broadcast (`roomIdStr`); needs a lookup to find its anchor.
  broadcast,

  /// An anchor's uid, the room identity.
  anchor,
}

/// A parsed KilaKila link.
@immutable
final class KilakilaLink {
  /// Creates a link.
  const new(this.kind, this.id);

  /// Broadcast or anchor.
  final KilakilaLinkKind kind;

  /// The broadcast id or the uid.
  final String id;

  @override
  bool operator ==(Object other) => other is KilakilaLink && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'KilakilaLink(${kind.name}, $id)';

  /// §1 public codec constants of the official website script
  /// (`uxin-security-url-crypto-v2.min.js`): not credentials.
  static const _keys = ['7cdyGRc6Sa93ilPt', 'c98be79a4347bc97'];
  static const _iv = '93x0ue23c2c9h8km';
  static const _salt = r'pR@Wv%Wju@Pl&bKc$GyUrPeO';

  static final _id = RegExp(r'^[1-9][0-9]{0,31}$');
  static const _roomHosts = {'live.kilakila.cn', 'www.hongdoufm.com'};
  static const _anchorHost = 'live.hongrenshuo.com.cn';

  /// §1 the link in [input] (a URL, possibly inside share text), or null
  /// when it is not a KilaKila room or anchor link or fails its signature.
  static KilakilaLink? parse(String input) {
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(input.trim());
    final text = match?.group(0) ?? input.trim();
    final uri = Uri.tryParse(text);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.hasFragment) return null;
    final roomHost = _roomHosts.contains(uri.host);
    final anchorHost = uri.host == _anchorHost;
    if (!roomHost && !anchorHost) return null;
    // The signature binds the path as sent, before any normalisation.
    final rawPath = RegExp('^[A-Za-z][A-Za-z0-9+.-]*://[^/?#]+([^?#]*)').firstMatch(text)?.group(1) ?? '';
    final query = uri.queryParameters;
    final String prefix;
    final KilakilaLinkKind kind;
    if (anchorHost && rawPath.startsWith('/index/roomuser/uid/')) {
      prefix = '/index/roomuser/uid/';
      kind = KilakilaLinkKind.anchor;
    } else if (roomHost && rawPath.startsWith('/zhubo/')) {
      prefix = '/zhubo/';
      kind = KilakilaLinkKind.anchor;
    } else if (roomHost && rawPath.startsWith('/room/')) {
      prefix = '/room/';
      kind = KilakilaLinkKind.broadcast;
    } else if (roomHost && (rawPath == '/PcLive/index/detail' || rawPath == '/PcLive/index/detail/')) {
      final encrypted = query['_specific_parameter'];
      if (encrypted == null) {
        final id = query['id'];
        return id != null && _id.hasMatch(id) ? KilakilaLink(KilakilaLinkKind.broadcast, id) : null;
      }
      if (query.containsKey('id') || query.containsKey('sign')) return null;
      final params = _decrypt(encrypted);
      if (params == null || params.containsKey('')) return null;
      final id = params['id'];
      if (id == null || !_id.hasMatch(id)) return null;
      final base = '${uri.origin}$rawPath?';
      return _signed(params, base, pathId: null) ? KilakilaLink(KilakilaLinkKind.broadcast, id) : null;
    } else {
      return null;
    }
    if (query.containsKey('id') || query.containsKey('_specific_parameter')) return null;
    final segment = Uri.decodeComponent(rawPath.substring(prefix.length));
    if (segment.isEmpty || segment.contains('/')) return null;
    if (_id.hasMatch(segment)) return KilakilaLink(kind, segment);
    if (prefix == '/zhubo/') return null;
    final params = _decrypt(segment);
    final id = params?['id'];
    if (params == null || id == null || !_id.hasMatch(id)) return null;
    return _signed(params, '${uri.origin}$prefix', pathId: id) ? KilakilaLink(kind, id) : null;
  }

  /// §1 decrypts a payload (URL-safe base64, AES-128-CBC, PKCS#7) with
  /// each public key in turn and parses the plaintext: `<id>?k=v&…` for
  /// path links, `k=v&…` for the detail page. Null when nothing decrypts to
  /// well-formed parameters.
  static Map<String, String>? _decrypt(String payload) {
    if (payload.length > 4096 || !RegExp(r'^[A-Za-z0-9_+/\-]+={0,2}$').hasMatch(payload)) return null;
    final List<int> bytes;
    try {
      bytes = base64.decode(base64.normalize(payload.replaceAll('-', '+').replaceAll('_', '/')));
    } on FormatException {
      return null;
    }
    if (bytes.isEmpty || bytes.length % 16 != 0) return null;
    for (final key in _keys) {
      try {
        final plain = utf8.decode(Aes128Cbc.decrypt(bytes, key: utf8.encode(key), iv: utf8.encode(_iv)));
        final params = _parameters(plain);
        if (params != null) return params;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  static Map<String, String>? _parameters(String plain) {
    if (plain.isEmpty || RegExp(r'[\x00-\x1f\x7f]').hasMatch(plain)) return null;
    final result = <String, String>{};
    var query = plain;
    final question = plain.indexOf('?');
    final pathForm = question >= 0;
    if (pathForm) {
      final id = plain.substring(0, question);
      if (!_id.hasMatch(id) || plain.indexOf('?', question + 1) >= 0) return null;
      result['id'] = id;
      query = plain.substring(question + 1);
    }
    for (final pair in query.split('&')) {
      final equal = pair.indexOf('=');
      if (equal <= 0) return null;
      var key = pair.substring(0, equal);
      var value = pair.substring(equal + 1);
      if (pathForm) {
        // Path payloads are URL-encoded (URLSearchParams); detail payloads
        // keep raw values.
        key = Uri.decodeQueryComponent(key);
        value = Uri.decodeQueryComponent(value);
      } else if (value.contains('=')) {
        return null;
      }
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(key) || result.containsKey(key)) return null;
      result[key] = value;
    }
    return result;
  }

  /// §1 `sign = md5(salt + base + canonical)`: for a path link carrying only
  /// the id the canonical form is the id; otherwise it is the other
  /// parameters sorted by name as `k=v&…` (a path link also appends
  /// `<id>?` to the base).
  static bool _signed(Map<String, String> params, String base, {required String? pathId}) {
    final sign = params['sign'];
    if (sign == null || !RegExp(r'^[0-9a-f]{32}$').hasMatch(sign)) return false;
    String canonical;
    var prefix = base;
    if (pathId != null && params.length == 2) {
      canonical = pathId;
    } else {
      if (pathId != null) prefix = '$base$pathId?';
      final keys = params.keys.where((key) => key != 'sign' && (pathId == null || key != 'id')).toList()..sort();
      canonical = keys.map((key) => '$key=${params[key]}').join('&');
    }
    return md5.convert(utf8.encode('$_salt$prefix$canonical')).toString() == sign;
  }
}
