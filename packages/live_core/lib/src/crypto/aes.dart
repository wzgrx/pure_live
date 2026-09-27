import 'dart:typed_data';

/// AES encryption (FIPS-197) in CBC mode with PKCS#7 padding, for the web
/// request envelopes of LOOK (NetEase `weapi`) and Bigo. Encryption only;
/// 128- and 256-bit keys. Written here instead of adding a crypto package
/// for two short requests; checked against the FIPS-197 vectors and OpenSSL.
abstract final class AesCbc {
  static final Uint8List _sbox = _makeSbox();

  static Uint8List _makeSbox() {
    final sbox = Uint8List(256);
    var p = 1;
    var q = 1;
    do {
      // p runs over the multiplicative group of GF(2^8); q is its inverse.
      p = p ^ ((p << 1) & 0xff) ^ ((p & 0x80) != 0 ? 0x1b : 0);
      q = (q ^ (q << 1)) & 0xff;
      q = (q ^ (q << 2)) & 0xff;
      q = (q ^ (q << 4)) & 0xff;
      if ((q & 0x80) != 0) q ^= 0x09;
      final x = q ^ _rotl8(q, 1) ^ _rotl8(q, 2) ^ _rotl8(q, 3) ^ _rotl8(q, 4);
      sbox[p] = (x ^ 0x63) & 0xff;
    } while (p != 1);
    sbox[0] = 0x63;
    return sbox;
  }

  static int _rotl8(int x, int shift) => ((x << shift) | (x >> (8 - shift))) & 0xff;

  static int _xtime(int x) => ((x << 1) ^ ((x & 0x80) != 0 ? 0x1b : 0)) & 0xff;

  /// The expanded key schedule: (rounds + 1) × 16 bytes.
  static Uint8List _expand(List<int> key) {
    final nk = key.length ~/ 4;
    if (key.length != 16 && key.length != 32) throw ArgumentError.value(key.length, 'key', 'must be 16 or 32 bytes');
    final rounds = nk + 6;
    final w = Uint8List(16 * (rounds + 1))..setRange(0, key.length, key);
    var rcon = 1;
    for (var i = nk; i < 4 * (rounds + 1); i++) {
      var t0 = w[4 * i - 4];
      var t1 = w[4 * i - 3];
      var t2 = w[4 * i - 2];
      var t3 = w[4 * i - 1];
      if (i % nk == 0) {
        final first = t0;
        t0 = _sbox[t1] ^ rcon;
        t1 = _sbox[t2];
        t2 = _sbox[t3];
        t3 = _sbox[first];
        rcon = _xtime(rcon);
      } else if (nk > 6 && i % nk == 4) {
        t0 = _sbox[t0];
        t1 = _sbox[t1];
        t2 = _sbox[t2];
        t3 = _sbox[t3];
      }
      w[4 * i] = w[4 * (i - nk)] ^ t0;
      w[4 * i + 1] = w[4 * (i - nk) + 1] ^ t1;
      w[4 * i + 2] = w[4 * (i - nk) + 2] ^ t2;
      w[4 * i + 3] = w[4 * (i - nk) + 3] ^ t3;
    }
    return w;
  }

  /// Encrypts one 16-byte [block] in place with the expanded key [w].
  static void _encryptBlock(Uint8List block, Uint8List w) {
    final rounds = w.length ~/ 16 - 1;
    for (var i = 0; i < 16; i++) {
      block[i] ^= w[i];
    }
    final tmp = Uint8List(16);
    for (var round = 1; round <= rounds; round++) {
      // SubBytes and ShiftRows (column-major state).
      for (var c = 0; c < 4; c++) {
        for (var r = 0; r < 4; r++) {
          tmp[4 * c + r] = _sbox[block[4 * ((c + r) % 4) + r]];
        }
      }
      if (round != rounds) {
        // MixColumns.
        for (var c = 0; c < 4; c++) {
          final a0 = tmp[4 * c];
          final a1 = tmp[4 * c + 1];
          final a2 = tmp[4 * c + 2];
          final a3 = tmp[4 * c + 3];
          final all = a0 ^ a1 ^ a2 ^ a3;
          tmp[4 * c] = a0 ^ all ^ _xtime(a0 ^ a1);
          tmp[4 * c + 1] = a1 ^ all ^ _xtime(a1 ^ a2);
          tmp[4 * c + 2] = a2 ^ all ^ _xtime(a2 ^ a3);
          tmp[4 * c + 3] = a3 ^ all ^ _xtime(a3 ^ a0);
        }
      }
      for (var i = 0; i < 16; i++) {
        block[i] = tmp[i] ^ w[16 * round + i];
      }
    }
  }

  /// Encrypts one block with [key] (the FIPS-197 test vectors use this).
  static Uint8List encryptBlock(List<int> key, List<int> block) {
    if (block.length != 16) throw ArgumentError.value(block.length, 'block', 'must be 16 bytes');
    final out = Uint8List.fromList(block);
    _encryptBlock(out, _expand(key));
    return out;
  }

  /// CBC encryption of [plain] with PKCS#7 padding.
  static Uint8List encrypt(List<int> plain, {required List<int> key, required List<int> iv}) {
    if (iv.length != 16) throw ArgumentError.value(iv.length, 'iv', 'must be 16 bytes');
    final w = _expand(key);
    final pad = 16 - plain.length % 16;
    final data = Uint8List(plain.length + pad)
      ..setRange(0, plain.length, plain)
      ..fillRange(plain.length, plain.length + pad, pad);
    final chain = Uint8List.fromList(iv);
    for (var offset = 0; offset < data.length; offset += 16) {
      final block = Uint8List.sublistView(data, offset, offset + 16);
      for (var i = 0; i < 16; i++) {
        block[i] ^= chain[i];
      }
      _encryptBlock(block, w);
      chain.setRange(0, 16, block);
    }
    return data;
  }
}
