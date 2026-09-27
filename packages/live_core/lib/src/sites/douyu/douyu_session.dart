import 'dart:convert';

/// §8.1 what a stored Douyu login cookie is worth (spec/sites/douyu.md).
enum DouyuSessionState {
  /// No cookie.
  none,

  /// A cookie without a session token: requests go out as a guest.
  guest,

  /// A token that has not expired, or whose end is unknown.
  valid,

  /// Expired, but LTP0 and the device id can renew it (§8.2).
  expiredRefreshable,

  /// Expired and nothing to renew it with.
  expired,
}

/// Pure helpers for the Douyu login cookie: fields, the session token and its
/// end, the renewal credentials and merging a renewal's `Set-Cookie` lines
/// (spec/sites/douyu.md §8). Values are never logged.
abstract final class DouyuSession {
  /// §8.1 the web `dy_auth` lasts seven days from when it was saved.
  static const webCookieLifetime = Duration(days: 7);

  /// §8.2 renew when less than a day is left.
  static const refreshMargin = Duration(days: 1);

  /// §8.1 session tokens in order of preference.
  static const tokenNames = ['acf_jwt_token', 'acf_auth', 'dy_auth'];

  /// §8.2 the long-term renewal key; it only ever goes to the passport (§8.3).
  static const longTermName = 'LTP0';

  /// §6.6 the device id the login belongs to.
  static const deviceIdName = 'dy_did';

  /// §8.4 fields that only the passport request's cookie carries.
  static const _passportFields = ['LTP0', 'acf_stk', 'acf_ccn', 'acf_ltkid', 'acf_ssid'];

  /// §8.2 `Set-Cookie` attributes, which are not fields.
  static const _attributes = {'path', 'domain', 'expires', 'max-age', 'samesite', 'secure', 'httponly'};

  static final _controls = RegExp('[\u0000-\u001f\u007f]');
  static final _validName = RegExp(r"^[A-Za-z0-9_!#$%&'*+.^`|~-]+$");

  /// [cookie] without a leading `Cookie:`, control characters or outer blanks.
  static String normalize(String cookie) =>
      cookie.replaceAll(_controls, '').trim().replaceFirst(RegExp(r'^Cookie:\s*', caseSensitive: false), '').trim();

  /// `name=value` fields of [cookie] in order; malformed names are skipped and
  /// a later field replaces an earlier one of the same name.
  static Map<String, String> fields(String cookie) {
    final result = <String, String>{};
    for (final part in normalize(cookie).split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      if (!_validName.hasMatch(name)) continue;
      result[name] = part.substring(separator + 1).trim();
    }
    return result;
  }

  /// The value of field [name] (case-insensitive), or null when absent or blank.
  static String? field(String cookie, String name) {
    final wanted = name.toLowerCase();
    for (final MapEntry(:key, :value) in fields(cookie).entries) {
      if (key.toLowerCase() == wanted) return value.isEmpty ? null : value;
    }
    return null;
  }

  /// §8.1 the session token: `acf_jwt_token`, else `acf_auth`, else `dy_auth`.
  static String? sessionToken(String cookie) {
    for (final name in tokenNames) {
      final value = field(cookie, name);
      if (value != null) return value;
    }
    return null;
  }

  /// The payload of a JWT, or null when [token] is not one.
  static Map<String, Object?>? jwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// §8.1 when the session ends: the JWT's `exp`, else [savedAt] plus seven
  /// days for the opaque `dy_auth`; null when nothing says (never guessed).
  static DateTime? expiry(String cookie, {DateTime? savedAt}) {
    final token = sessionToken(cookie);
    if (token == null) return null;
    final exp = jwtPayload(token)?['exp'];
    final seconds = exp is num ? exp.toInt() : int.tryParse('${exp ?? ''}');
    if (seconds != null && seconds > 0) return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return savedAt?.add(webCookieLifetime);
  }

  /// §8.2 LTP0 and the device id for a renewal: what the user typed, else the
  /// cookie's own fields, else the separately stored ones. The device id never
  /// falls back to the process DID.
  static ({String? ltp0, String? did}) credentials(
    String cookie, {
    String? typedLtp0,
    String? typedDid,
    String? storedLtp0,
    String? storedDid,
  }) => (
    ltp0: _blank(typedLtp0) ?? field(cookie, longTermName) ?? _blank(storedLtp0),
    did: _blank(typedDid) ?? field(cookie, deviceIdName) ?? _blank(storedDid),
  );

  static String? _blank(String? value) {
    final trimmed = value?.replaceAll(_controls, '').trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// §8.1 the state of [cookie] at [now]; [ltp0] and [did] are the renewal
  /// credentials from [credentials].
  static DouyuSessionState state(String cookie, {required DateTime now, DateTime? savedAt, String? ltp0, String? did}) {
    if (normalize(cookie).isEmpty) return DouyuSessionState.none;
    if (sessionToken(cookie) == null) return DouyuSessionState.guest;
    final end = expiry(cookie, savedAt: savedAt);
    if (end == null || end.isAfter(now)) return DouyuSessionState.valid;
    return ltp0 != null && did != null ? DouyuSessionState.expiredRefreshable : DouyuSessionState.expired;
  }

  /// §8.2 whether to renew before a play request: no token, or less than a day
  /// left. An unknown end is not renewed.
  static bool shouldRenew(String cookie, {required DateTime now, DateTime? savedAt}) {
    if (sessionToken(cookie) == null) return true;
    final end = expiry(cookie, savedAt: savedAt);
    return end != null && !now.isBefore(end.subtract(refreshMargin));
  }

  /// §8.4 a cookie copied from the passport request: renewal fields and no
  /// session token. It is not a login and must not be sent to play endpoints.
  static bool isPassportCookie(String cookie) =>
      sessionToken(cookie) == null && _passportFields.any((name) => field(cookie, name) != null);

  /// §8.2 [cookie] with a renewal's `Set-Cookie` [lines] merged in: fields the
  /// response did not mention stay (LTP0 among them), emptied ones are
  /// removed, attributes are ignored.
  static String merge(String cookie, Iterable<String> lines) {
    final merged = fields(cookie);
    for (final line in lines) {
      final pair = line.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      if (!_validName.hasMatch(name) || _attributes.contains(name.toLowerCase())) continue;
      final value = pair.substring(separator + 1).replaceAll(_controls, '').trim();
      if (value.isEmpty) {
        merged.remove(name);
      } else {
        merged[name] = value;
      }
    }
    return merged.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }
}
