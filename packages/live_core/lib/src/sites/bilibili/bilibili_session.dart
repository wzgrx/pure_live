part of 'bilibili_parse.dart';

/// State of a QR login poll (§8.3). Every state is a step of the flow, not
/// a failure.
enum BilibiliQrState {
  /// 86101: not scanned yet.
  waiting,

  /// 86090: scanned, waiting for the user to confirm on the phone.
  scanned,

  /// 86038: the code expired; generate a new one.
  expired,

  /// 0: confirmed; the login cookie is in the response's `Set-Cookie`
  /// headers, which the adapter reads and then verifies (§8.2).
  confirmed,
}

/// Pure parsing of Bilibili's session plumbing: guest buvid, request
/// headers, WBI keys and the string to sign, the `w_webid` access id,
/// danmaku credentials, QR login and the account check.
abstract final class BilibiliSession {
  /// §8.1 `x/frontend/finger/spi`: `data.b_3` is buvid3, `data.b_4` buvid4.
  static ({String buvid3, String buvid4}) buvid(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'finger/spi')['data']);
    final buvid3 = jsonString(data?['b_3']);
    if (buvid3 == null) throw ApiChanged(_site, 'finger/spi: no b_3 (${_snippet(body)})');
    return (buvid3: buvid3, buvid4: jsonString(data?['b_4']) ?? '');
  }

  /// §6.3 the cookie of API and media requests: the guest buvid pair, or the
  /// login cookie with the pair appended when it has no `buvid3`.
  static String cookie({required String buvid3, required String buvid4, String loginCookie = ''}) {
    final stored = loginCookie.trim();
    if (stored.isEmpty) return 'buvid3=$buvid3;buvid4=$buvid4;';
    if (RegExp(r'(?:^|;)\s*buvid3=').hasMatch(stored)) return stored;
    return '${stored.endsWith(';') ? stored : '$stored;'}buvid3=$buvid3;buvid4=$buvid4;';
  }

  /// §6.3 API request headers (api.live, api, live domains).
  static Map<String, String> apiHeaders(String cookie) => {
    'user-agent': BilibiliParse.userAgent,
    'referer': 'https://live.bilibili.com/',
    'cookie': cookie,
  };

  /// §6.4 `x/web-interface/nav`: the WBI keys are the file names (without
  /// extension) of `data.wbi_img.img_url` and `sub_url`. A guest gets code
  /// -101 with the keys present (recorded), so the code only matters when
  /// the keys are missing.
  static ({String imgKey, String subKey}) wbiKeys(String body, {int status = 200}) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    final image = _object(_object(_object(decoded)?['data'])?['wbi_img']);
    String? key(Object? url) {
      final text = jsonString(url);
      if (text == null) return null;
      final name = text.substring(text.lastIndexOf('/') + 1).split('.').first;
      return name.isEmpty ? null : name;
    }

    final imgKey = key(image?['img_url']);
    final subKey = key(image?['sub_url']);
    if (imgKey != null && subKey != null && status >= 200 && status < 300) return (imgKey: imgKey, subKey: subKey);
    _checked(body, status: status, what: 'nav');
    throw ApiChanged(_site, 'nav: no wbi_img keys (${_snippet(body)})');
  }

  static const _mixinTable = [
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38, //
    41, 13, 37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36,
    20, 34, 44, 52,
  ];

  /// §6.4 mixin key: imgKey + subKey permuted by the fixed 64-entry table,
  /// first 32 characters.
  static String mixinKey(String imgKey, String subKey) {
    final origin = '$imgKey$subKey';
    if (origin.length < 64) throw ApiChanged(_site, 'WBI keys too short (${origin.length} characters)');
    return [for (final index in _mixinTable) origin[index]].join().substring(0, 32);
  }

  static final _unsafe = RegExp("[!'()*]");

  /// §6.4 steps 1–4: [params] plus `wts`, sorted by key, `!'()*` removed from
  /// values, percent-encoded. Send this query with `&w_rid=` +
  /// `md5(query + mixinKey)` appended; the md5 is the adapter's
  /// (`BilibiliSite.wbiSign`). Spaces encode as `%20`, like the browser's
  /// `encodeURIComponent` (legacy used `+`; no signed parameter has one).
  static String wbiQuery(Map<String, String> params, {required int wts}) {
    final all = {...params, 'wts': '$wts'};
    final keys = all.keys.toList()..sort();
    return [
      for (final key in keys) '${Uri.encodeComponent(key)}=${Uri.encodeComponent(all[key]!.replaceAll(_unsafe, ''))}',
    ].join('&');
  }

  /// §2.2 `w_webid`: `"access_id":"…"` in the `live.bilibili.com/lol` page,
  /// backslashes removed.
  static String accessId(String html) {
    final id = RegExp('"access_id":"(.*?)"').firstMatch(html)?.group(1)?.replaceAll(r'\', '');
    if (id == null || id.isEmpty) throw const ApiChanged(_site, 'lol page: no access_id');
    return id;
  }

  /// §7.1 `getDanmuInfo` (WBI signed, long room id): the token and the
  /// WebSocket endpoints, the general gateway first, then `host_list` with
  /// `wss_port` (443 omitted, default 443), without duplicates. An empty
  /// token is [ApiChanged].
  static ({String token, List<Uri> servers}) danmakuInfo(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'getDanmuInfo')['data']);
    final token = jsonString(data?['token']);
    if (token == null) throw const ApiChanged(_site, 'getDanmuInfo: empty token');
    final servers = <String>['wss://broadcastlv.chat.bilibili.com/sub'];
    for (final item in _list(data?['host_list'])) {
      final host = jsonString(_object(item)?['host']);
      if (host == null) continue;
      final port = jsonInt(_object(item)?['wss_port']) ?? 443;
      final endpoint = 'wss://$host${port == 443 ? '' : ':$port'}/sub';
      if (!servers.contains(endpoint)) servers.add(endpoint);
    }
    return (token: token, servers: [for (final server in servers) Uri.parse(server)]);
  }

  /// §8.2 danmaku uid: 0 without a cookie; else `DedeUserID` from the same
  /// cookie; else the verified [storedUid] when positive; else 0.
  static int danmakuUid({required String cookie, required int storedUid}) {
    if (cookie.trim().isEmpty) return 0;
    final match = RegExp(r'(?:^|;)\s*DedeUserID=(\d+)(?:;|$)', caseSensitive: false).firstMatch(cookie);
    final uid = int.tryParse(match?.group(1) ?? '');
    if (uid != null && uid > 0) return uid;
    return storedUid > 0 ? storedUid : 0;
  }

  /// §8.3 `qrcode/generate`: the key to poll with and the https URL to encode.
  static ({String key, Uri url}) qrCode(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'qrcode/generate')['data']);
    final key = jsonString(data?['qrcode_key']);
    final url = jsonUrl(data?['url']);
    if (key == null || url == null || !url.isScheme('https')) {
      throw ApiChanged(_site, 'qrcode/generate: no key or https url (${_snippet(body)})');
    }
    return (key: key, url: url);
  }

  /// §8.3 `qrcode/poll`: `data.code` 86101, 86090, 86038 and 0 are flow
  /// states; any other code is [ApiChanged].
  static BilibiliQrState qrPoll(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'qrcode/poll')['data']);
    return switch (jsonInt(data?['code'])) {
      86101 => BilibiliQrState.waiting,
      86090 => BilibiliQrState.scanned,
      86038 => BilibiliQrState.expired,
      0 => BilibiliQrState.confirmed,
      final code => throw ApiChanged(_site, 'qrcode/poll: code $code ${jsonString(data?['message']) ?? ''}'.trim()),
    };
  }

  /// §8.2 `x/member/web/account`: signed in when code is 0 and `data.uname`
  /// is set (`data.mid` is the uid); -101 is [NeedsLogin] (the adapter clears
  /// a stored cookie as expired).
  static ({int uid, String name}) account(String body, {int status = 200}) {
    final data = _object(_checked(body, status: status, what: 'member/web/account')['data']);
    final name = jsonString(data?['uname']);
    final uid = jsonInt(data?['mid']);
    if (name == null || uid == null || uid <= 0) {
      throw ApiChanged(_site, 'member/web/account: no uname or mid (${_snippet(body)})');
    }
    return (uid: uid, name: name);
  }
}
