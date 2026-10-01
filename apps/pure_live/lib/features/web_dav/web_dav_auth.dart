import 'dart:convert';
import 'dart:math' as math;

/// One challenge from a `WWW-Authenticate` header (RFC 7235).
final class AuthChallenge {
  /// Creates the challenge.
  const new(this.scheme, this.params);

  /// The scheme in lower case (`basic`, `digest`, ...).
  final String scheme;

  /// Parameters by lower-case name, quotes removed.
  final Map<String, String> params;
}

/// Reads every challenge in [headers] (each `WWW-Authenticate` line can hold
/// several, separated by commas; quoted values can hold commas too).
List<AuthChallenge> parseAuthChallenges(Iterable<String> headers) {
  final challenges = <AuthChallenge>[];
  for (final header in headers) {
    var i = 0;
    Map<String, String>? params;
    bool isDelimiter(int at) => ' \t,="'.contains(header[at]);
    void skipSpace() {
      while (i < header.length && (header[i] == ' ' || header[i] == '\t')) {
        i++;
      }
    }

    while (i < header.length) {
      if (isDelimiter(i)) {
        i++;
        continue;
      }
      final start = i;
      while (i < header.length && !isDelimiter(i)) {
        i++;
      }
      final token = header.substring(start, i);
      skipSpace();
      if (i < header.length && header[i] == '=') {
        i++;
        skipSpace();
        final value = StringBuffer();
        if (i < header.length && header[i] == '"') {
          i++;
          while (i < header.length && header[i] != '"') {
            if (header[i] == r'\' && i + 1 < header.length) i++;
            value.write(header[i++]);
          }
          i++;
        } else {
          while (i < header.length && header[i] != ',' && header[i] != ' ' && header[i] != '\t') {
            value.write(header[i++]);
          }
        }
        params?[token.toLowerCase()] = value.toString();
      } else {
        params = <String, String>{};
        challenges.add(AuthChallenge(token.toLowerCase(), params));
      }
    }
  }
  return challenges;
}

/// A Digest challenge this client can answer (RFC 7616 and RFC 2617):
/// algorithm MD5 or MD5-sess, `qop=auth` or no qop, as 3.x's webdav_client.
final class DigestChallenge {
  const new _({
    required this.realm,
    required this.nonce,
    required this.algorithm,
    required this.opaque,
    required this.qopAuth,
    required this.stale,
  });

  /// The Digest challenge in [challenge], or null when it is another scheme
  /// or asks for something not supported (SHA-256, `auth-int` only, no nonce).
  static DigestChallenge? from(AuthChallenge challenge) {
    if (challenge.scheme != 'digest') return null;
    final params = challenge.params;
    final nonce = params['nonce'];
    if (nonce == null || nonce.isEmpty) return null;
    final algorithm = params['algorithm'];
    if (algorithm != null && !const {'md5', 'md5-sess'}.contains(algorithm.toLowerCase())) return null;
    final qop = params['qop'];
    final qops = [
      for (final option in (qop ?? '').split(','))
        if (option.trim().isNotEmpty) option.trim().toLowerCase(),
    ];
    if (qops.isNotEmpty && !qops.contains('auth')) return null;
    return DigestChallenge._(
      realm: params['realm'] ?? '',
      nonce: nonce,
      algorithm: algorithm,
      opaque: params['opaque'],
      qopAuth: qops.isNotEmpty,
      stale: params['stale']?.toLowerCase() == 'true',
    );
  }

  /// The protection space.
  final String realm;

  /// The server's nonce.
  final String nonce;

  /// The algorithm as the server wrote it, or null (MD5).
  final String? algorithm;

  /// Data the server wants back unchanged.
  final String? opaque;

  /// Whether the answer uses `qop=auth` (with `nc` and `cnonce`); otherwise
  /// the RFC 2069 form.
  final bool qopAuth;

  /// Whether the previous answer was right but its nonce had expired.
  final bool stale;
}

/// The `Authorization` value answering [challenge] for a [method] request to
/// [uri] (the request target: path and query). [nc] counts the requests made
/// with this nonce, from 1; [cnonce] is the client's random value.
String digestAuthorization({
  required DigestChallenge challenge,
  required String username,
  required String password,
  required String method,
  required String uri,
  required int nc,
  required String cnonce,
}) {
  final count = nc.toRadixString(16).padLeft(8, '0');
  var ha1 = md5Hex(utf8.encode('$username:${challenge.realm}:$password'));
  if (challenge.algorithm?.toLowerCase() == 'md5-sess') {
    ha1 = md5Hex(utf8.encode('$ha1:${challenge.nonce}:$cnonce'));
  }
  final ha2 = md5Hex(utf8.encode('$method:$uri'));
  final response = md5Hex(
    utf8.encode(
      challenge.qopAuth ? '$ha1:${challenge.nonce}:$count:$cnonce:auth:$ha2' : '$ha1:${challenge.nonce}:$ha2',
    ),
  );
  String quote(String value) => '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  return [
    'Digest username=${quote(username)}',
    'realm=${quote(challenge.realm)}',
    'nonce=${quote(challenge.nonce)}',
    'uri=${quote(uri)}',
    if (challenge.algorithm != null) 'algorithm=${challenge.algorithm}',
    'response=${quote(response)}',
    if (challenge.qopAuth) ...['qop=auth', 'nc=$count', 'cnonce=${quote(cnonce)}'],
    if (challenge.opaque != null) 'opaque=${quote(challenge.opaque!)}',
  ].join(', ');
}

/// A random client nonce: 16 hex digits, as 3.x's webdav_client.
String randomCnonce() {
  final random = math.Random.secure();
  return [for (var i = 0; i < 8; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

const List<int> _md5Shifts = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, //
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, //
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
];

final List<int> _md5Constants = [
  for (var i = 0; i < 64; i++) (math.sin(i + 1).abs() * 4294967296).floor() & 0xffffffff,
];

/// MD5 of [data] as 32 lower-case hex digits (RFC 1321). Digest
/// authentication needs nothing else, so the app does not add a hash package.
String md5Hex(List<int> data) {
  const mask = 0xffffffff;
  final length = data.length;
  final padded = [
    ...data,
    0x80,
    ...List<int>.filled((55 - length) % 64, 0),
    for (var i = 0; i < 8; i++) ((length * 8) >> (8 * i)) & 0xff,
  ];
  var a0 = 0x67452301;
  var b0 = 0xefcdab89;
  var c0 = 0x98badcfe;
  var d0 = 0x10325476;
  final words = List<int>.filled(16, 0);
  for (var chunk = 0; chunk < padded.length; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      final at = chunk + i * 4;
      words[i] = padded[at] | padded[at + 1] << 8 | padded[at + 2] << 16 | padded[at + 3] << 24;
    }
    var a = a0;
    var b = b0;
    var c = c0;
    var d = d0;
    for (var i = 0; i < 64; i++) {
      final int f;
      final int g;
      if (i < 16) {
        f = (b & c) | (~b & mask & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & mask & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | (~d & mask));
        g = (7 * i) % 16;
      }
      final sum = (a + f + _md5Constants[i] + words[g]) & mask;
      final shift = _md5Shifts[i];
      a = d;
      d = c;
      c = b;
      b = (b + ((sum << shift | sum >> (32 - shift)) & mask)) & mask;
    }
    a0 = (a0 + a) & mask;
    b0 = (b0 + b) & mask;
    c0 = (c0 + c) & mask;
    d0 = (d0 + d) & mask;
  }
  final hex = StringBuffer();
  for (final word in [a0, b0, c0, d0]) {
    for (var i = 0; i < 4; i++) {
      hex.write(((word >> (8 * i)) & 0xff).toRadixString(16).padLeft(2, '0'));
    }
  }
  return hex.toString();
}
