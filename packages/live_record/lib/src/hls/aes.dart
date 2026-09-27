import 'dart:typed_data';

/// AES-128 (FIPS-197) in CBC mode with PKCS#7 padding (NIST SP 800-38A),
/// for HLS `METHOD=AES-128` segments (RFC 8216 §5.2). Keys stay in memory
/// only; nothing here touches the disk (spec/modules/record.md §13).
///
/// Not constant-time: the key protects nothing on this device, it only
/// undoes the CDN's transport encryption.
final class HlsAes128 {
  /// Expands [key] (16 bytes); throws [ArgumentError] otherwise.
  factory(List<int> key) {
    if (key.length != 16) throw ArgumentError.value(key.length, 'key', 'AES-128 keys are 16 bytes');
    _Tables.ready();
    const rounds = 10;
    const total = 4 * (rounds + 1);
    final encrypt = Uint32List(total);
    for (var i = 0; i < 4; i++) {
      encrypt[i] = key[4 * i] << 24 | key[4 * i + 1] << 16 | key[4 * i + 2] << 8 | key[4 * i + 3];
    }
    var rcon = 1;
    for (var i = 4; i < total; i++) {
      var t = encrypt[i - 1];
      if (i % 4 == 0) {
        t = _subWord(t << 8 & 0xFFFFFFFF | t >>> 24) ^ rcon << 24;
        rcon = _xtime(rcon);
      }
      encrypt[i] = encrypt[i - 4] ^ t;
    }
    // The equivalent inverse cipher: round keys in reverse order, the inner
    // ones through InvMixColumns.
    final decrypt = Uint32List(total);
    for (var round = 0; round <= rounds; round++) {
      for (var column = 0; column < 4; column++) {
        final word = encrypt[4 * (rounds - round) + column];
        decrypt[4 * round + column] = round == 0 || round == rounds
            ? word
            : _Tables.dec0[_Tables.sbox[word >>> 24]] ^
                  _Tables.dec1[_Tables.sbox[word >>> 16 & 0xFF]] ^
                  _Tables.dec2[_Tables.sbox[word >>> 8 & 0xFF]] ^
                  _Tables.dec3[_Tables.sbox[word & 0xFF]];
      }
    }
    return HlsAes128._(encrypt, decrypt);
  }

  new _(this._encryptKeys, this._decryptKeys);

  /// Block size in bytes.
  static const blockSize = 16;

  static const _rounds = 10;

  final Uint32List _encryptKeys;
  final Uint32List _decryptKeys;

  /// The IV HLS uses when `EXT-X-KEY` has none: the media sequence number as
  /// a 128-bit big-endian integer (RFC 8216 §5.2).
  static Uint8List sequenceIv(int sequence) {
    final iv = Uint8List(16);
    var value = sequence;
    for (var i = 15; i >= 8 && value > 0; i--) {
      iv[i] = value & 0xFF;
      value >>= 8;
    }
    return iv;
  }

  /// Decrypts [data] under [iv] and removes the PKCS#7 padding. Throws
  /// [FormatException] when [data] is not whole blocks or the padding is bad
  /// (a wrong key, IV or a truncated segment).
  Uint8List decrypt(Uint8List data, List<int> iv) {
    _checkIv(iv);
    if (data.isEmpty || data.length % blockSize != 0) {
      throw FormatException('AES-128 data of ${data.length} bytes is not whole blocks');
    }
    final out = Uint8List(data.length);
    final previous = Uint32List(4);
    _load(iv, 0, previous);
    final block = Uint32List(4);
    final state = Uint32List(4);
    for (var offset = 0; offset < data.length; offset += blockSize) {
      _load(data, offset, block);
      state.setAll(0, block);
      _decryptBlock(state);
      for (var i = 0; i < 4; i++) {
        state[i] ^= previous[i];
      }
      _store(state, out, offset);
      previous.setAll(0, block);
    }
    final pad = out.last;
    if (pad == 0 || pad > blockSize) throw const FormatException('bad AES-128 padding');
    for (var i = out.length - pad; i < out.length; i++) {
      if (out[i] != pad) throw const FormatException('bad AES-128 padding');
    }
    return Uint8List.sublistView(out, 0, out.length - pad);
  }

  /// Pads [plain] (PKCS#7) and encrypts it under [iv] (test streams).
  Uint8List encrypt(List<int> plain, List<int> iv) {
    _checkIv(iv);
    final pad = blockSize - plain.length % blockSize;
    final out = Uint8List(plain.length + pad)
      ..setAll(0, plain)
      ..fillRange(plain.length, plain.length + pad, pad);
    final state = Uint32List(4);
    _load(iv, 0, state);
    final block = Uint32List(4);
    for (var offset = 0; offset < out.length; offset += blockSize) {
      _load(out, offset, block);
      for (var i = 0; i < 4; i++) {
        state[i] ^= block[i];
      }
      _encryptBlock(state);
      _store(state, out, offset);
    }
    return out;
  }

  static void _checkIv(List<int> iv) {
    if (iv.length != blockSize) throw ArgumentError.value(iv.length, 'iv', 'the IV is 16 bytes');
  }

  static void _load(List<int> bytes, int offset, Uint32List words) {
    for (var i = 0; i < 4; i++) {
      final at = offset + 4 * i;
      words[i] = bytes[at] << 24 | bytes[at + 1] << 16 | bytes[at + 2] << 8 | bytes[at + 3];
    }
  }

  static void _store(Uint32List words, Uint8List out, int offset) {
    for (var i = 0; i < 4; i++) {
      final word = words[i];
      final at = offset + 4 * i;
      out[at] = word >>> 24;
      out[at + 1] = word >>> 16 & 0xFF;
      out[at + 2] = word >>> 8 & 0xFF;
      out[at + 3] = word & 0xFF;
    }
  }

  void _encryptBlock(Uint32List s) {
    final k = _encryptKeys;
    var s0 = s[0] ^ k[0];
    var s1 = s[1] ^ k[1];
    var s2 = s[2] ^ k[2];
    var s3 = s[3] ^ k[3];
    final [e0, e1, e2, e3] = _Tables.encrypt;
    for (var round = 1; round < _rounds; round++) {
      final at = 4 * round;
      final t0 = e0[s0 >>> 24] ^ e1[s1 >>> 16 & 0xFF] ^ e2[s2 >>> 8 & 0xFF] ^ e3[s3 & 0xFF] ^ k[at];
      final t1 = e0[s1 >>> 24] ^ e1[s2 >>> 16 & 0xFF] ^ e2[s3 >>> 8 & 0xFF] ^ e3[s0 & 0xFF] ^ k[at + 1];
      final t2 = e0[s2 >>> 24] ^ e1[s3 >>> 16 & 0xFF] ^ e2[s0 >>> 8 & 0xFF] ^ e3[s1 & 0xFF] ^ k[at + 2];
      final t3 = e0[s3 >>> 24] ^ e1[s0 >>> 16 & 0xFF] ^ e2[s1 >>> 8 & 0xFF] ^ e3[s2 & 0xFF] ^ k[at + 3];
      s0 = t0;
      s1 = t1;
      s2 = t2;
      s3 = t3;
    }
    final box = _Tables.sbox;
    const at = 4 * _rounds;
    s[0] = _word(box[s0 >>> 24], box[s1 >>> 16 & 0xFF], box[s2 >>> 8 & 0xFF], box[s3 & 0xFF]) ^ k[at];
    s[1] = _word(box[s1 >>> 24], box[s2 >>> 16 & 0xFF], box[s3 >>> 8 & 0xFF], box[s0 & 0xFF]) ^ k[at + 1];
    s[2] = _word(box[s2 >>> 24], box[s3 >>> 16 & 0xFF], box[s0 >>> 8 & 0xFF], box[s1 & 0xFF]) ^ k[at + 2];
    s[3] = _word(box[s3 >>> 24], box[s0 >>> 16 & 0xFF], box[s1 >>> 8 & 0xFF], box[s2 & 0xFF]) ^ k[at + 3];
  }

  void _decryptBlock(Uint32List s) {
    final k = _decryptKeys;
    var s0 = s[0] ^ k[0];
    var s1 = s[1] ^ k[1];
    var s2 = s[2] ^ k[2];
    var s3 = s[3] ^ k[3];
    final d0 = _Tables.dec0;
    final d1 = _Tables.dec1;
    final d2 = _Tables.dec2;
    final d3 = _Tables.dec3;
    for (var round = 1; round < _rounds; round++) {
      final at = 4 * round;
      final t0 = d0[s0 >>> 24] ^ d1[s3 >>> 16 & 0xFF] ^ d2[s2 >>> 8 & 0xFF] ^ d3[s1 & 0xFF] ^ k[at];
      final t1 = d0[s1 >>> 24] ^ d1[s0 >>> 16 & 0xFF] ^ d2[s3 >>> 8 & 0xFF] ^ d3[s2 & 0xFF] ^ k[at + 1];
      final t2 = d0[s2 >>> 24] ^ d1[s1 >>> 16 & 0xFF] ^ d2[s0 >>> 8 & 0xFF] ^ d3[s3 & 0xFF] ^ k[at + 2];
      final t3 = d0[s3 >>> 24] ^ d1[s2 >>> 16 & 0xFF] ^ d2[s1 >>> 8 & 0xFF] ^ d3[s0 & 0xFF] ^ k[at + 3];
      s0 = t0;
      s1 = t1;
      s2 = t2;
      s3 = t3;
    }
    final box = _Tables.inverse;
    const at = 4 * _rounds;
    s[0] = _word(box[s0 >>> 24], box[s3 >>> 16 & 0xFF], box[s2 >>> 8 & 0xFF], box[s1 & 0xFF]) ^ k[at];
    s[1] = _word(box[s1 >>> 24], box[s0 >>> 16 & 0xFF], box[s3 >>> 8 & 0xFF], box[s2 & 0xFF]) ^ k[at + 1];
    s[2] = _word(box[s2 >>> 24], box[s1 >>> 16 & 0xFF], box[s0 >>> 8 & 0xFF], box[s3 & 0xFF]) ^ k[at + 2];
    s[3] = _word(box[s3 >>> 24], box[s2 >>> 16 & 0xFF], box[s1 >>> 8 & 0xFF], box[s0 & 0xFF]) ^ k[at + 3];
  }

  static int _word(int a, int b, int c, int d) => a << 24 | b << 16 | c << 8 | d;

  static int _subWord(int word) => _word(
    _Tables.sbox[word >>> 24],
    _Tables.sbox[word >>> 16 & 0xFF],
    _Tables.sbox[word >>> 8 & 0xFF],
    _Tables.sbox[word & 0xFF],
  );
}

int _xtime(int value) => (value << 1 ^ ((value & 0x80) != 0 ? 0x1B : 0)) & 0xFF;

int _multiply(int a, int b) {
  var result = 0;
  var x = a;
  var y = b;
  while (y > 0) {
    if ((y & 1) != 0) result ^= x;
    x = _xtime(x);
    y >>= 1;
  }
  return result;
}

/// Lookup tables, computed once from the field arithmetic instead of
/// shipped as literals.
abstract final class _Tables {
  static final sbox = Uint8List(256);
  static final inverse = Uint8List(256);
  static final dec0 = Uint32List(256);
  static final dec1 = Uint32List(256);
  static final dec2 = Uint32List(256);
  static final dec3 = Uint32List(256);
  static final encrypt = [Uint32List(256), Uint32List(256), Uint32List(256), Uint32List(256)];
  static var _ready = false;

  static void ready() {
    if (_ready) return;
    _ready = true;
    // S-box: multiplicative inverse in GF(2^8), then the affine transform.
    var p = 1;
    var q = 1;
    do {
      p = p ^ (p << 1 & 0xFF) ^ ((p & 0x80) != 0 ? 0x1B : 0);
      q ^= q << 1;
      q ^= q << 2;
      q ^= q << 4;
      q &= 0xFF;
      if ((q & 0x80) != 0) q ^= 0x09;
      final x = q ^ _rotl8(q, 1) ^ _rotl8(q, 2) ^ _rotl8(q, 3) ^ _rotl8(q, 4);
      sbox[p] = (x ^ 0x63) & 0xFF;
    } while (p != 1);
    sbox[0] = 0x63;
    for (var i = 0; i < 256; i++) {
      inverse[sbox[i]] = i;
    }
    for (var i = 0; i < 256; i++) {
      final s = sbox[i];
      final e = _multiply(s, 2) << 24 | s << 16 | s << 8 | _multiply(s, 3);
      encrypt[0][i] = e;
      encrypt[1][i] = _rotr(e, 8);
      encrypt[2][i] = _rotr(e, 16);
      encrypt[3][i] = _rotr(e, 24);
      final v = inverse[i];
      final d = _multiply(v, 14) << 24 | _multiply(v, 9) << 16 | _multiply(v, 13) << 8 | _multiply(v, 11);
      dec0[i] = d;
      dec1[i] = _rotr(d, 8);
      dec2[i] = _rotr(d, 16);
      dec3[i] = _rotr(d, 24);
    }
  }

  static int _rotl8(int x, int shift) => (x << shift | x >> (8 - shift)) & 0xFF;

  static int _rotr(int x, int shift) => (x >>> shift | x << (32 - shift)) & 0xFFFFFFFF;
}
