import 'dart:typed_data';

/// AES (FIPS-197) in CBC mode with PKCS#7 padding (NIST SP 800-38A), for
/// AcFun's chat link (spec/sites/acfun.md §7). It is the only cipher a chat
/// protocol needs, so it lives here instead of adding a dependency.
///
/// Not constant-time: it protects nothing on this device, it only speaks
/// the platform's wire format.
final class AesCbc {
  /// Expands [key] (16, 24 or 32 bytes); throws [ArgumentError] otherwise.
  factory(List<int> key) {
    if (key.length != 16 && key.length != 24 && key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'AES keys are 16, 24 or 32 bytes');
    }
    _Tables.ready();
    final words = key.length ~/ 4;
    final rounds = words + 6;
    final total = 4 * (rounds + 1);
    final encrypt = Uint32List(total);
    for (var i = 0; i < words; i++) {
      encrypt[i] = key[4 * i] << 24 | key[4 * i + 1] << 16 | key[4 * i + 2] << 8 | key[4 * i + 3];
    }
    var rcon = 1;
    for (var i = words; i < total; i++) {
      var t = encrypt[i - 1];
      if (i % words == 0) {
        t = _subWord(t << 8 & 0xFFFFFFFF | t >>> 24) ^ rcon << 24;
        rcon = _xtime(rcon);
      } else if (words > 6 && i % words == 4) {
        t = _subWord(t);
      }
      encrypt[i] = encrypt[i - words] ^ t;
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
    return AesCbc._(rounds, encrypt, decrypt);
  }

  new _(this._rounds, this._encryptKeys, this._decryptKeys);

  /// Block size in bytes.
  static const blockSize = 16;

  final int _rounds;
  final Uint32List _encryptKeys;
  final Uint32List _decryptKeys;

  /// Pads [plain] (PKCS#7) and encrypts it under [iv]; the result holds the
  /// ciphertext only.
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

  /// Decrypts [cipher] under [iv] and removes the padding; throws
  /// [FormatException] on a partial block or bad padding (a wrong key).
  Uint8List decrypt(List<int> cipher, List<int> iv) {
    _checkIv(iv);
    if (cipher.isEmpty || cipher.length % blockSize != 0) {
      throw FormatException('AES-CBC: ${cipher.length} bytes is not whole blocks');
    }
    final out = Uint8List(cipher.length);
    final previous = Uint32List(4);
    _load(iv, 0, previous);
    final block = Uint32List(4);
    final next = Uint32List(4);
    for (var offset = 0; offset < cipher.length; offset += blockSize) {
      _load(cipher, offset, block);
      next.setAll(0, block);
      _decryptBlock(block);
      for (var i = 0; i < 4; i++) {
        block[i] ^= previous[i];
      }
      _store(block, out, offset);
      previous.setAll(0, next);
    }
    final pad = out.last;
    if (pad < 1 || pad > blockSize) throw const FormatException('AES-CBC: bad padding');
    for (var i = out.length - pad; i < out.length; i++) {
      if (out[i] != pad) throw const FormatException('AES-CBC: bad padding');
    }
    return Uint8List.sublistView(out, 0, out.length - pad);
  }

  void _encryptBlock(Uint32List s) {
    final k = _encryptKeys;
    var s0 = s[0] ^ k[0];
    var s1 = s[1] ^ k[1];
    var s2 = s[2] ^ k[2];
    var s3 = s[3] ^ k[3];
    final e0 = _Tables.enc0;
    final e1 = _Tables.enc1;
    final e2 = _Tables.enc2;
    final e3 = _Tables.enc3;
    for (var round = 1; round < _rounds; round++) {
      final r = 4 * round;
      final t0 = e0[s0 >>> 24] ^ e1[s1 >>> 16 & 0xFF] ^ e2[s2 >>> 8 & 0xFF] ^ e3[s3 & 0xFF] ^ k[r];
      final t1 = e0[s1 >>> 24] ^ e1[s2 >>> 16 & 0xFF] ^ e2[s3 >>> 8 & 0xFF] ^ e3[s0 & 0xFF] ^ k[r + 1];
      final t2 = e0[s2 >>> 24] ^ e1[s3 >>> 16 & 0xFF] ^ e2[s0 >>> 8 & 0xFF] ^ e3[s1 & 0xFF] ^ k[r + 2];
      final t3 = e0[s3 >>> 24] ^ e1[s0 >>> 16 & 0xFF] ^ e2[s1 >>> 8 & 0xFF] ^ e3[s2 & 0xFF] ^ k[r + 3];
      s0 = t0;
      s1 = t1;
      s2 = t2;
      s3 = t3;
    }
    final r = 4 * _rounds;
    final box = _Tables.sbox;
    s[0] = _last(box, s0, s1, s2, s3) ^ k[r];
    s[1] = _last(box, s1, s2, s3, s0) ^ k[r + 1];
    s[2] = _last(box, s2, s3, s0, s1) ^ k[r + 2];
    s[3] = _last(box, s3, s0, s1, s2) ^ k[r + 3];
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
      final r = 4 * round;
      final t0 = d0[s0 >>> 24] ^ d1[s3 >>> 16 & 0xFF] ^ d2[s2 >>> 8 & 0xFF] ^ d3[s1 & 0xFF] ^ k[r];
      final t1 = d0[s1 >>> 24] ^ d1[s0 >>> 16 & 0xFF] ^ d2[s3 >>> 8 & 0xFF] ^ d3[s2 & 0xFF] ^ k[r + 1];
      final t2 = d0[s2 >>> 24] ^ d1[s1 >>> 16 & 0xFF] ^ d2[s0 >>> 8 & 0xFF] ^ d3[s3 & 0xFF] ^ k[r + 2];
      final t3 = d0[s3 >>> 24] ^ d1[s2 >>> 16 & 0xFF] ^ d2[s1 >>> 8 & 0xFF] ^ d3[s0 & 0xFF] ^ k[r + 3];
      s0 = t0;
      s1 = t1;
      s2 = t2;
      s3 = t3;
    }
    final r = 4 * _rounds;
    final box = _Tables.inverse;
    s[0] = _last(box, s0, s3, s2, s1) ^ k[r];
    s[1] = _last(box, s1, s0, s3, s2) ^ k[r + 1];
    s[2] = _last(box, s2, s1, s0, s3) ^ k[r + 2];
    s[3] = _last(box, s3, s2, s1, s0) ^ k[r + 3];
  }

  static int _last(Uint8List box, int a, int b, int c, int d) =>
      box[a >>> 24] << 24 | box[b >>> 16 & 0xFF] << 16 | box[c >>> 8 & 0xFF] << 8 | box[d & 0xFF];

  static void _checkIv(List<int> iv) {
    if (iv.length != blockSize) throw ArgumentError.value(iv.length, 'iv', 'the IV is one 16-byte block');
  }

  static void _load(List<int> bytes, int offset, Uint32List into) {
    for (var i = 0; i < 4; i++) {
      final at = offset + 4 * i;
      into[i] = bytes[at] << 24 | bytes[at + 1] << 16 | bytes[at + 2] << 8 | bytes[at + 3];
    }
  }

  static void _store(Uint32List words, Uint8List out, int offset) {
    for (var i = 0; i < 4; i++) {
      final word = words[i];
      final at = offset + 4 * i;
      out[at] = word >>> 24;
      out[at + 1] = word >>> 16;
      out[at + 2] = word >>> 8;
      out[at + 3] = word;
    }
  }

  static int _subWord(int word) {
    final box = _Tables.sbox;
    return box[word >>> 24] << 24 | box[word >>> 16 & 0xFF] << 16 | box[word >>> 8 & 0xFF] << 8 | box[word & 0xFF];
  }
}

/// Multiplication by x in GF(2^8).
int _xtime(int value) => (value << 1 ^ (value & 0x80 != 0 ? 0x1B : 0)) & 0xFF;

int _multiply(int a, int b) {
  var result = 0;
  var x = a;
  for (var y = b; y > 0; y >>= 1) {
    if (y & 1 != 0) result ^= x;
    x = _xtime(x);
  }
  return result;
}

/// S-boxes and round tables, built once from the field arithmetic instead
/// of pasted as literals.
abstract final class _Tables {
  static final sbox = Uint8List(256);
  static final inverse = Uint8List(256);
  static final enc0 = Uint32List(256);
  static final enc1 = Uint32List(256);
  static final enc2 = Uint32List(256);
  static final enc3 = Uint32List(256);
  static final dec0 = Uint32List(256);
  static final dec1 = Uint32List(256);
  static final dec2 = Uint32List(256);
  static final dec3 = Uint32List(256);
  static var _built = false;

  static int _rotate(int word) => word >>> 8 | (word & 0xFF) << 24;

  static int _rotateByte(int value, int by) => (value << by | value >>> (8 - by)) & 0xFF;

  static void ready() {
    if (_built) return;
    _built = true;
    // Walk the multiplicative group with generator 3: p runs over 3^k,
    // q over its inverse 3^-k, so q is the inverse of p.
    var p = 1;
    var q = 1;
    do {
      p = p ^ _xtime(p);
      q ^= q << 1;
      q ^= q << 2;
      q ^= q << 4;
      q &= 0xFF;
      if (q & 0x80 != 0) q ^= 0x09;
      sbox[p] = q ^ _rotateByte(q, 1) ^ _rotateByte(q, 2) ^ _rotateByte(q, 3) ^ _rotateByte(q, 4) ^ 0x63;
    } while (p != 1);
    sbox[0] = 0x63;
    for (var i = 0; i < 256; i++) {
      inverse[sbox[i]] = i;
    }
    for (var i = 0; i < 256; i++) {
      final s = sbox[i];
      final e = _multiply(s, 2) << 24 | s << 16 | s << 8 | _multiply(s, 3);
      enc0[i] = e;
      enc1[i] = _rotate(e);
      enc2[i] = _rotate(enc1[i]);
      enc3[i] = _rotate(enc2[i]);
      final v = inverse[i];
      final d = _multiply(v, 14) << 24 | _multiply(v, 9) << 16 | _multiply(v, 13) << 8 | _multiply(v, 11);
      dec0[i] = d;
      dec1[i] = _rotate(d);
      dec2[i] = _rotate(dec1[i]);
      dec3[i] = _rotate(dec2[i]);
    }
  }
}
