/// Removes secrets from text before it reaches the local log or a
/// diagnostics bundle (constitution rule 8, store.md §0.3): cookies, tokens,
/// passwords, pairing codes, credentials in URLs and signed URL queries.
///
/// The rules are deliberately broad: a redacted harmless value costs less
/// than a leaked cookie.
abstract final class LogScrubber {
  /// What replaces a removed value.
  static const redacted = '<redacted>';

  // Header lines whose whole value is secret.
  static final _headers = RegExp(
    r'\b(cookie|set-cookie|authorization|proxy-authorization|x-purelive-pairing)(\s*[:=]\s*)[^\r\n]*',
    caseSensitive: false,
  );

  // user:password@ in URLs.
  static final _userInfo = RegExp(r'(\b[a-z][a-z0-9+.-]*://)[^/\s@]+@', caseSensitive: false);

  // Query strings of http(s) URLs: signed stream URLs carry their signature
  // there (wsSecret, txSecret, sign, auth_key, expires, ...).
  static final _query = RegExp(r'(\bhttps?://[^\s?#"<>]+)\?[^\s#"<>]*', caseSensitive: false);

  static const _secretNames =
      'sessdata|bili_jct|dedeuserid__ckmd5|access_token|refresh_token|access_key|auth_key|token|tokens|password|'
      'passwd|pwd|secret|passphrase|ltp0|acf_auth|acf_stk|acf_ltkid|dy_did|did|sessionid|session_id|sid|'
      'csrf|csrf_token|ticket|signature|sign|wssecret|txsecret|pairing|pairingcode|code_verifier|cookie|cookies';

  // "name": "value, spaces included" with a secret-looking name.
  static final _quotedPairs = RegExp('\\b($_secretNames)\\b(["\']?\\s*[:=]\\s*)(["\'])(.*?)\\3', caseSensitive: false);

  // name=value, name: value with a secret-looking name (not already
  // quoted or redacted).
  static final _pairs = RegExp(
    '\\b($_secretNames)\\b(["\']?\\s*[:=]\\s*)(?!["\'<])([^"\'&;,\\s}\\]]+)',
    caseSensitive: false,
  );

  // Long opaque tokens (cookies, JWTs, signatures) without a telling name.
  static final _opaque = RegExp(r'[A-Za-z0-9_\-+=%.]{48,}');

  /// [text] with every secret-looking value replaced by [redacted].
  static String scrub(String text) {
    if (text.isEmpty) return text;
    return text
        .replaceAllMapped(_headers, (m) => '${m[1]}${m[2]}$redacted')
        .replaceAllMapped(_userInfo, (m) => '${m[1]}$redacted@')
        .replaceAllMapped(_query, (m) => '${m[1]}?$redacted')
        .replaceAllMapped(_quotedPairs, (m) => '${m[1]}${m[2]}${m[3]}$redacted${m[3]}')
        .replaceAllMapped(_pairs, (m) => '${m[1]}${m[2]}$redacted')
        .replaceAll(_opaque, redacted);
  }
}
