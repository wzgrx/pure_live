import 'dart:typed_data';

/// SHA-256 of [data] as lowercase hex (FIPS 180-4). live_net has no crypto
/// dependency; the tests only need to compare digests.
String sha256Hex(List<int> data) {
  final length = data.length;
  final padded = Uint8List(((length + 8) >> 6) + 1 << 6)..setRange(0, length, data);
  padded[length] = 0x80;
  final bits = length * 8;
  for (var i = 0; i < 8; i++) {
    padded[padded.length - 1 - i] = bits >> (8 * i) & 0xff;
  }
  final hash = Uint32List.fromList(_initial);
  final w = Uint32List(64);
  final view = ByteData.sublistView(padded);
  for (var block = 0; block < padded.length; block += 64) {
    for (var t = 0; t < 16; t++) {
      w[t] = view.getUint32(block + 4 * t);
    }
    for (var t = 16; t < 64; t++) {
      final a = w[t - 15];
      final b = w[t - 2];
      final s0 = _rotr(a, 7) ^ _rotr(a, 18) ^ a >> 3;
      final s1 = _rotr(b, 17) ^ _rotr(b, 19) ^ b >> 10;
      w[t] = w[t - 16] + s0 + w[t - 7] + s1;
    }
    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];
    for (var t = 0; t < 64; t++) {
      final t1 = h + (_rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25)) + ((e & f) ^ (~e & g)) + _k[t] + w[t] & _mask;
      final t2 = (_rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c)) & _mask;
      h = g;
      g = f;
      f = e;
      e = d + t1 & _mask;
      d = c;
      c = b;
      b = a;
      a = t1 + t2 & _mask;
    }
    hash[0] += a;
    hash[1] += b;
    hash[2] += c;
    hash[3] += d;
    hash[4] += e;
    hash[5] += f;
    hash[6] += g;
    hash[7] += h;
  }
  return [for (final word in hash) word.toRadixString(16).padLeft(8, '0')].join();
}

/// CRC-32 of [data] as defined in RFC 7932 Appendix C.
int crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    var c = (crc ^ byte) & 0xff;
    for (var k = 0; k < 8; k++) {
      c = c & 1 != 0 ? 0xedb88320 ^ c >> 1 : c >> 1;
    }
    crc = c ^ crc >> 8;
  }
  return crc ^ 0xffffffff;
}

const int _mask = 0xffffffff;

int _rotr(int x, int n) => (x >> n | x << (32 - n)) & _mask;

const List<int> _initial = [
  // FIPS 180-4 section 5.3.3.
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

const List<int> _k = [
  // FIPS 180-4 section 4.2.2.
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];
