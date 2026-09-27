import 'dart:typed_data';

/// AES-128 decryption in CBC mode with PKCS#7 padding (FIPS 197,
/// SP 800-38A), for the platforms whose public share links are encrypted
/// with published constants (spec/sites/kilakila.md §1). Decryption only.
abstract final class Aes128Cbc {
  static final Uint8List _sbox = _buildSbox();
  static final Uint8List _inverse = _buildInverse(_sbox);

  /// Decrypts [data] with [key] and [iv] (16 bytes each) and removes the
  /// PKCS#7 padding; throws [FormatException] when the length or the
  /// padding is wrong.
  static Uint8List decrypt(List<int> data, {required List<int> key, required List<int> iv}) {
    final out = decryptBlocks(data, key: key, iv: iv);
    final pad = out.last;
    if (pad < 1 || pad > 16 || out.sublist(out.length - pad).any((byte) => byte != pad)) {
      throw const FormatException('Bad PKCS#7 padding');
    }
    return Uint8List.sublistView(out, 0, out.length - pad);
  }

  /// Decrypts whole blocks without touching the padding.
  static Uint8List decryptBlocks(List<int> data, {required List<int> key, required List<int> iv}) {
    if (key.length != 16 || iv.length != 16) throw const FormatException('AES-128 needs 16-byte key and IV');
    if (data.isEmpty || data.length % 16 != 0) throw const FormatException('Ciphertext is not whole blocks');
    final rounds = _expand(key);
    final out = Uint8List(data.length);
    final previous = Uint8List.fromList(iv);
    final block = Uint8List(16);
    for (var offset = 0; offset < data.length; offset += 16) {
      for (var i = 0; i < 16; i++) {
        block[i] = data[offset + i];
      }
      final plain = _decryptBlock(block, rounds);
      for (var i = 0; i < 16; i++) {
        out[offset + i] = plain[i] ^ previous[i];
        previous[i] = data[offset + i];
      }
    }
    return out;
  }

  static int _xtime(int value) => ((value << 1) ^ ((value & 0x80) != 0 ? 0x1b : 0)) & 0xff;

  static int _multiply(int a, int b) {
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

  /// The S-box from the multiplicative inverse in GF(2^8) and the affine map.
  static Uint8List _buildSbox() {
    final box = Uint8List(256);
    for (var value = 0; value < 256; value++) {
      var inverse = 0;
      if (value != 0) {
        for (var candidate = 1; candidate < 256; candidate++) {
          if (_multiply(value, candidate) == 1) {
            inverse = candidate;
            break;
          }
        }
      }
      var result = inverse;
      for (var shift = 1; shift <= 4; shift++) {
        result ^= ((inverse << shift) | (inverse >> (8 - shift))) & 0xff;
      }
      box[value] = result ^ 0x63;
    }
    return box;
  }

  static Uint8List _buildInverse(Uint8List box) {
    final inverse = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      inverse[box[i]] = i;
    }
    return inverse;
  }

  /// Key expansion: 11 round keys of 16 bytes.
  static List<Uint8List> _expand(List<int> key) {
    final words = Uint8List(176)..setRange(0, 16, key);
    var rcon = 1;
    for (var i = 16; i < 176; i += 4) {
      var t0 = words[i - 4];
      var t1 = words[i - 3];
      var t2 = words[i - 2];
      var t3 = words[i - 1];
      if (i % 16 == 0) {
        final first = t0;
        t0 = _sbox[t1] ^ rcon;
        t1 = _sbox[t2];
        t2 = _sbox[t3];
        t3 = _sbox[first];
        rcon = _xtime(rcon);
      }
      words[i] = words[i - 16] ^ t0;
      words[i + 1] = words[i - 15] ^ t1;
      words[i + 2] = words[i - 14] ^ t2;
      words[i + 3] = words[i - 13] ^ t3;
    }
    return [for (var round = 0; round <= 10; round++) Uint8List.sublistView(words, round * 16, round * 16 + 16)];
  }

  static Uint8List _decryptBlock(Uint8List input, List<Uint8List> rounds) {
    final state = Uint8List.fromList(input);
    void addRoundKey(Uint8List key) {
      for (var i = 0; i < 16; i++) {
        state[i] ^= key[i];
      }
    }

    void inverseShiftAndSub() {
      final copy = Uint8List.fromList(state);
      // Column-major state: byte (row r, column c) is at 4c + r.
      for (var column = 0; column < 4; column++) {
        for (var row = 0; row < 4; row++) {
          state[4 * ((column + row) % 4) + row] = _inverse[copy[4 * column + row]];
        }
      }
    }

    void inverseMixColumns() {
      for (var column = 0; column < 4; column++) {
        final a = state[4 * column];
        final b = state[4 * column + 1];
        final c = state[4 * column + 2];
        final d = state[4 * column + 3];
        state[4 * column] = _multiply(a, 14) ^ _multiply(b, 11) ^ _multiply(c, 13) ^ _multiply(d, 9);
        state[4 * column + 1] = _multiply(a, 9) ^ _multiply(b, 14) ^ _multiply(c, 11) ^ _multiply(d, 13);
        state[4 * column + 2] = _multiply(a, 13) ^ _multiply(b, 9) ^ _multiply(c, 14) ^ _multiply(d, 11);
        state[4 * column + 3] = _multiply(a, 11) ^ _multiply(b, 13) ^ _multiply(c, 9) ^ _multiply(d, 14);
      }
    }

    addRoundKey(rounds[10]);
    for (var round = 9; round >= 1; round--) {
      inverseShiftAndSub();
      addRoundKey(rounds[round]);
      inverseMixColumns();
    }
    inverseShiftAndSub();
    addRoundKey(rounds[0]);
    return state;
  }
}
