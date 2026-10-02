"""Generates the Brotli decoder's test vectors (packages/live_net/test/data/brotli/).

Every expected result comes from the reference implementation: the `brotli`
Python module (Debian's python3-brotli, or `pip install brotli` in a virtual
environment) for compressing and decompressing, and libbrotlicommon for the
dictionary word transforms. Neither is a dependency of the repository; the
vectors are committed.

    python3 tools/brotli/gen_test_vectors.py --official <google/brotli checkout>/tests/testdata

Output, each group as `<group>.bin` (the streams, concatenated) and
`<group>.json` (name, offset and size of each stream, and the expected
result: the output's length and SHA-256, or "error"):

- official: part of google/brotli's tests/testdata (MIT licence);
- reference: inputs compressed by the reference encoder at every quality,
  every window size and each mode, two of them past 16 MiB;
- crafted: streams written by the small encoder below, to reach what the
  reference encoder never writes (LSB6 and MSB6 context modes, every kind of
  prefix code header, context maps with run lengths and move-to-front, block
  switches of every kind, every short distance code, direct distance codes,
  all 121 transforms, metadata and uncompressed meta-blocks, every window
  size), and invalid streams, one per check the decoder makes;
- mutations.json: truncated, bit-flipped, re-windowed and extended copies of
  the streams above, as operations on a named stream, with the reference
  decoder's verdict;
- transforms.json: SHA-256 of every static dictionary word under every
  transform, per word length, from libbrotlicommon.

The crafted streams' expected output is also checked against this script's own
model of the format, so a mistake in either shows up here; with
BROTLI_DEBUG_DIR set, a stream they disagree on is saved there.
"""
import argparse
import base64
import ctypes
import ctypes.util
import hashlib
import heapq
import json
import math
import os
import random
import re
import struct
import sys
from pathlib import Path

import brotli

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'packages/live_net/test/data/brotli'
SEED = 20260929

NDBITS = [0, 0, 0, 0, 10, 10, 11, 11, 10, 10, 10, 10, 10, 9, 9, 8, 7, 7, 8, 7, 7, 6, 6, 5, 5]
DOFFSET = [0] * 26
for _n in range(25):
    DOFFSET[_n + 1] = DOFFSET[_n] + (_n * (1 << NDBITS[_n]) if _n >= 4 else 0)
INSERT_BASE = [0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 18, 26, 34, 50, 66, 98, 130, 194, 322, 578, 1090, 2114, 6210, 22594]
INSERT_BITS = [0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, 24]
COPY_BASE = [2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 22, 30, 38, 54, 70, 102, 134, 198, 326, 582, 1094, 2118]
COPY_BITS = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 24]
BLOCK_BASE = [1, 5, 9, 13, 17, 25, 33, 41, 49, 65, 81, 97, 113, 145, 177, 209, 241, 305, 369, 497, 753, 1265, 2289,
              4337, 8433, 16625]
BLOCK_BITS = [2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 7, 8, 9, 10, 11, 12, 13, 24]
INSERT_RANGE = [0, 0, 0, 0, 8, 8, 0, 16, 8, 16, 16]
COPY_RANGE = [0, 8, 0, 8, 0, 8, 16, 0, 16, 8, 16]
CODE_LENGTH_ORDER = [1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15]
# The fixed code of code length code lengths: value -> (bits in stream order as an integer, length).
CODE_LENGTH_CODE = {0: (0b00, 2), 1: (0b0111, 4), 2: (0b011, 3), 3: (0b10, 2), 4: (0b01, 2), 5: (0b1111, 4)}


# Reference implementation.

class _Dictionary(ctypes.Structure):
    _fields_ = [('size_bits_by_length', ctypes.c_uint8 * 32), ('offsets_by_length', ctypes.c_uint32 * 32),
                ('data_size', ctypes.c_size_t), ('data', ctypes.POINTER(ctypes.c_uint8))]


class Reference:
    def __init__(self):
        name = ctypes.util.find_library('brotlicommon')
        if not name:
            sys.exit('libbrotlicommon not found')
        self.lib = ctypes.CDLL(name)
        self.lib.BrotliGetDictionary.restype = ctypes.POINTER(_Dictionary)
        self.lib.BrotliGetTransforms.restype = ctypes.c_void_p
        self.lib.BrotliTransformDictionaryWord.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int,
                                                           ctypes.c_void_p, ctypes.c_int]
        self.lib.BrotliTransformDictionaryWord.restype = ctypes.c_int
        dictionary = self.lib.BrotliGetDictionary().contents
        self.dictionary = ctypes.string_at(dictionary.data, dictionary.data_size)
        self.dictionary_address = ctypes.cast(dictionary.data, ctypes.c_void_p).value
        self.transforms = self.lib.BrotliGetTransforms()
        self.buffer = ctypes.create_string_buffer(64)

    def word(self, length, index, transform):
        """The static dictionary word of `length` bytes at `index` under `transform`."""
        offset = DOFFSET[length] + index * length
        size = self.lib.BrotliTransformDictionaryWord(self.buffer, self.dictionary_address + offset, length,
                                                      self.transforms, transform)
        return self.buffer.raw[:size]

    @staticmethod
    def decompress(data):
        try:
            return brotli.decompress(data)
        except brotli.error:
            return None


def verdict(output):
    if output is None:
        return 'error'
    return {'length': len(output), 'sha256': hashlib.sha256(output).hexdigest()}


# Bit writer and prefix codes.

class Bits:
    """Writes bits least significant first, as the format reads them."""

    def __init__(self):
        self.out = bytearray()
        self.acc = 0
        self.count = 0

    def write(self, value, count):
        assert 0 <= value < (1 << count) or (count == 0 and value == 0), (value, count)
        self.acc |= value << self.count
        self.count += count
        while self.count >= 8:
            self.out.append(self.acc & 0xff)
            self.acc >>= 8
            self.count -= 8

    def write_code(self, code, length):
        """A canonical prefix code, most significant bit first."""
        for i in reversed(range(length)):
            self.write((code >> i) & 1, 1)

    def align(self, fill=0):
        if self.count:
            self.write(fill & ((1 << (8 - self.count)) - 1), 8 - self.count)

    def raw(self, data):
        assert self.count == 0
        self.out += data

    def bytes(self):
        tail = bytes([self.acc]) if self.count else b''
        return bytes(self.out) + tail


def canonical(lengths):
    """Canonical codes (RFC 7932 section 3.2) for {symbol: length}."""
    count = [0] * 16
    for length in lengths.values():
        count[length] += 1
    count[0] = 0
    code, next_code = 0, [0] * 16
    for bits in range(1, 16):
        code = (code + count[bits - 1]) << 1
        next_code[bits] = code
    codes = {}
    for symbol in sorted(lengths):
        length = lengths[symbol]
        if length:
            codes[symbol] = (next_code[length], length)
            next_code[length] += 1
    return codes


def huffman_lengths(counts, limit):
    """Code lengths for {symbol: count} (at least two symbols), at most `limit`: Huffman's, with the counts
    flattened until the longest code fits."""
    weights = dict(counts)
    for _ in range(30):
        heap = [(weight, i, [symbol]) for i, (symbol, weight) in enumerate(sorted(weights.items()))]
        heapq.heapify(heap)
        depth = {symbol: 0 for symbol in weights}
        tie = len(heap)
        while len(heap) > 1:
            a, _, sa = heapq.heappop(heap)
            b, _, sb = heapq.heappop(heap)
            for symbol in sa + sb:
                depth[symbol] += 1
            heapq.heappush(heap, (a + b, tie, sa + sb))
            tie += 1
        if max(depth.values()) <= limit:
            return depth
        weights = {symbol: int(weight ** 0.7) + 1 for symbol, weight in weights.items()}
    return balanced_lengths(sorted(counts))


def balanced_lengths(symbols):
    """A complete code over two or more symbols with lengths L - 1 and L."""
    n = len(symbols)
    width = (n - 1).bit_length()
    short = (1 << width) - n
    return {symbol: width - 1 if i < short else width for i, symbol in enumerate(symbols)}


class Code:
    """A prefix code chosen for the symbols used, and its header."""

    def __init__(self, rng, size, counts, faults=()):
        self.size = size
        used = sorted(symbol for symbol, count in counts.items() if count > 0)
        if not used:
            used = [rng.randrange(size)]
        self.faults = faults
        if 'simple' in faults:
            used = used[:4] if len(used) > 1 else used + [next(s for s in range(size) if s != used[0])]
        if 'simple' in faults or (len(used) <= 4 and 'complex' not in faults and rng.random() < 0.6):
            self.kind = 'simple'
            symbols = list(used)
            extra = rng.randrange(0, 5 - len(symbols)) if rng.random() < 0.3 else 0
            while extra and len(symbols) < min(4, size):
                candidate = rng.randrange(size)
                if candidate not in symbols:
                    symbols.append(candidate)
                    extra -= 1
            rng.shuffle(symbols)
            self.symbols = symbols
            self.tree_select = rng.randrange(2) if len(symbols) == 4 else 0
            shape = {1: [0], 2: [1, 1], 3: [1, 2, 2], 4: [[2, 2, 2, 2], [1, 2, 3, 3]][self.tree_select]}[len(symbols)]
            self.lengths = dict(zip(symbols, shape))
        else:
            self.kind = 'complex'
            if len(used) == 1:
                used.append(next(s for s in range(size) if s != used[0]))
            if size == 256 and len(used) > 128 and rng.random() < 0.5:
                self.lengths = {s: 8 for s in range(256)}  # RFC 7932's single-symbol code length code example
            elif rng.random() < 0.3:
                self.lengths = balanced_lengths(used)
            else:
                weights = {s: counts.get(s, 0) + 1 for s in used}
                if rng.random() < 0.3:  # skewed, for long codes and second-level tables
                    order = list(used)
                    rng.shuffle(order)
                    weights = {s: int(1.5 ** min(i, 45)) + counts.get(s, 0) for i, s in enumerate(order)}
                self.lengths = huffman_lengths(weights, 15)
        self.codes = canonical(self.lengths) if len(self.lengths) > 1 else {s: (0, 0) for s in self.lengths}

    def emit(self, bits, symbol):
        if symbol not in self.codes:
            assert self.faults, symbol  # a deliberately broken code; the stream is rejected before this
            return
        code, length = self.codes[symbol]
        bits.write_code(code, length)

    def write_header(self, bits, rng):
        if self.kind == 'simple':
            self._write_simple(bits)
        else:
            self._write_complex(bits, rng)

    def _write_simple(self, bits):
        width = (self.size - 1).bit_length()
        bits.write(1, 2)
        bits.write(len(self.symbols) - 1, 2)
        symbols = list(self.symbols)
        if 'duplicate-symbol' in self.faults and len(symbols) >= 2:
            symbols[1] = symbols[0]
        if 'symbol-range' in self.faults:
            symbols[0] = (1 << width) - 1
            assert symbols[0] >= self.size
        for symbol in symbols:
            bits.write(symbol, width)
        if len(symbols) == 4:
            bits.write(self.tree_select, 1)

    def _write_complex(self, bits, rng):
        depth = [self.lengths.get(s, 0) for s in range(self.size)]
        while depth and depth[-1] == 0:
            depth.pop()
        if 'incomplete' in self.faults:
            # Drop the longest code: the code no longer fills the space.
            longest = max(range(len(depth)), key=lambda s: depth[s])
            depth[longest] = 0
            while depth[-1] == 0:
                depth.pop()
        tokens = rle_tokens(depth, rng.random() < 0.7, rng.random() < 0.7)
        if 'lengths-overflow' in self.faults:
            # Before the last length: a zero, then a run of zeros past the end of the alphabet.
            covered = covered_symbols(tokens[:-1]) + 1
            tokens[-1:-1] = [(0, 0, 0)] + zero_run(max(3, self.size - covered + 1))
        histogram = {}
        for symbol, _, _ in tokens:
            histogram[symbol] = histogram.get(symbol, 0) + 1
        if len(histogram) == 1:
            symbol = next(iter(histogram))
            cl_lengths = {symbol: rng.randrange(1, 6)}
            cl_codes = {symbol: (0, 0)}
        else:
            cl_lengths = huffman_lengths(histogram, 5)
            cl_codes = canonical(cl_lengths)
        values = [cl_lengths.get(CODE_LENGTH_ORDER[i], 0) for i in range(18)]
        skips = [0]
        if values[0] == 0 and values[1] == 0:
            skips.append(2)
            if values[2] == 0:
                skips.append(3)
        hskip = rng.choice(skips)
        if len(cl_lengths) == 1:
            end = 18
        else:
            end = max(i for i in range(18) if values[i]) + 1
        if 'cl-space' in self.faults:
            # One code length code made longer: the code no longer fills the space.
            values = list(values)
            first = next(i for i in range(hskip, end) if 0 < values[i] < 5)
            values[first] = 5
            end = 18
        bits.write(hskip, 2)
        for i in range(hskip, end):
            pattern, length = CODE_LENGTH_CODE[values[i]]
            bits.write(pattern, length)
        for symbol, extra, extra_bits in tokens:
            code, length = cl_codes[symbol]
            bits.write_code(code, length)
            bits.write(extra, extra_bits)


def zero_run(reps):
    """Code length symbols for `reps` zeros (enc/entropy_encode.c)."""
    tokens = []
    if reps == 11:
        tokens.append((0, 0, 0))
        reps -= 1
    if reps < 3:
        return tokens + [(0, 0, 0)] * reps
    reps -= 3
    run = []
    while True:
        run.append((17, reps & 7, 3))
        reps >>= 3
        if reps == 0:
            break
        reps -= 1
    return tokens + run[::-1]


def covered_symbols(tokens):
    """Symbols the code length symbols `tokens` give lengths to (RFC 7932 section 3.5)."""
    symbol, repeat, repeat_length, previous = 0, 0, None, 8
    for code, extra, _ in tokens:
        if code < 16:
            repeat = 0
            symbol += 1
            if code:
                previous = code
            continue
        length, extra_bits = (previous, 2) if code == 16 else (0, 3)
        if repeat_length != length:
            repeat, repeat_length = 0, length
        before = repeat
        if repeat > 0:
            repeat = (repeat - 2) << extra_bits
        repeat += extra + 3
        symbol += repeat - before
    return symbol


def rle_tokens(depth, rle_zero, rle_nonzero):
    """Code length symbols for `depth` as the reference encoder writes them (enc/entropy_encode.c)."""
    tokens = []

    def zeros(reps):
        tokens.extend(zero_run(reps))

    def repeats(previous, value, reps):
        if previous != value:
            tokens.append((value, 0, 0))
            reps -= 1
        if reps == 7:
            tokens.append((value, 0, 0))
            reps -= 1
        if reps < 3:
            tokens.extend([(value, 0, 0)] * reps)
            return
        reps -= 3
        run = []
        while True:
            run.append((16, reps & 3, 2))
            reps >>= 2
            if reps == 0:
                break
            reps -= 1
        tokens.extend(reversed(run))

    previous = 8
    i = 0
    while i < len(depth):
        value = depth[i]
        reps = 1
        if (value != 0 and rle_nonzero) or (value == 0 and rle_zero):
            while i + reps < len(depth) and depth[i + reps] == value:
                reps += 1
        if value == 0:
            zeros(reps)
        else:
            repeats(previous, value, reps)
            previous = value
        i += reps
    return tokens


def write_count(bits, n):
    """NBLTYPES / NTREES (1..256)."""
    v = n - 1
    if v == 0:
        bits.write(0, 1)
    elif v == 1:
        bits.write(1, 1)
        bits.write(0, 3)
    else:
        width = v.bit_length() - 1
        bits.write(1, 1)
        bits.write(width, 3)
        bits.write(v - (1 << width), width)


def write_window(bits, wbits):
    if wbits == 16:
        bits.write(0, 1)
    elif wbits >= 18:
        bits.write(1, 1)
        bits.write(wbits - 17, 3)
    elif wbits == 17:
        bits.write(1, 1)
        bits.write(0, 3)
        bits.write(0, 3)
    else:
        bits.write(1, 1)
        bits.write(0, 3)
        bits.write(wbits - 8, 3)


def code_for(value, base, extra):
    for code in range(len(base)):
        if base[code] <= value < base[code] + (1 << extra[code]):
            return code, value - base[code]
    raise ValueError(value)


def mtf(values):
    table = list(range(256))
    out = []
    for value in values:
        index = table.index(value)
        out.append(index)
        table.pop(index)
        table.insert(0, value)
    return out


# The crafter: a small encoder that writes chosen features and models the output.

def context_id(mode, p1, p2):
    if mode == 0:
        return p1 & 0x3f
    if mode == 1:
        return p1 >> 2
    if mode == 2:
        return LUT0[p1] | LUT1[p2]
    return (LUT2[p1] << 3) | LUT2[p2]


class Crafter:
    def __init__(self, reference, rng, wbits, faults=()):
        self.ref = reference
        self.rng = rng
        self.wbits = wbits
        self.window = (1 << wbits) - 16
        self.faults = set(faults)
        self.output = bytearray()
        self.transforms_used = set()
        self.ring = [16, 15, 11, 4]  # fourth-to-last ... last
        self.bits = Bits()
        write_window(self.bits, wbits)

    # Distances.

    def short_distance(self, code):
        last, second = self.ring[3], self.ring[2]
        if code < 4:
            return self.ring[3 - code]
        delta = [-1, 1, -2, 2, -3, 3][(code - 4) % 6]
        return (last if code < 10 else second) + delta

    def distance_options(self, distance, npostfix, ndirect, allow_implicit):
        options = []
        if allow_implicit and distance == self.ring[3]:
            options.append(('implicit',))
        for code in range(16):
            if self.short_distance(code) == distance:
                options.append(('code', code, 0, 0))
        if 1 <= distance <= ndirect:
            options.append(('code', 15 + distance, 0, 0))
        general = self.general_distance(distance, npostfix, ndirect)
        if general:
            options.append(general)
        return options

    @staticmethod
    def general_distance(distance, npostfix, ndirect):
        rest = distance - ndirect - 1
        if rest < 0:
            return None
        lcode = rest & ((1 << npostfix) - 1)
        high = rest >> npostfix
        for code in range(16 + ndirect, 16 + ndirect + (48 << npostfix)):
            value = code - ndirect - 16
            if value & ((1 << npostfix) - 1) != lcode:
                continue
            nbits = 1 + (value >> (npostfix + 1))
            offset = ((2 + ((value >> npostfix) & 1)) << nbits) - 4
            if offset <= high < offset + (1 << nbits):
                return ('code', code, high - offset, nbits)
        return None

    def remember(self, distance):
        self.ring = self.ring[1:] + [distance]

    # Meta-blocks.

    def metadata(self, last, payload):
        bits = self.bits
        bits.write(1 if last else 0, 1)
        if last:
            bits.write(0, 1)
        bits.write(3, 2)
        bits.write(1 if 'reserved' in self.faults else 0, 1)
        if not payload:
            bits.write(0, 2)
        else:
            v = len(payload) - 1
            nbytes = max(1, (v.bit_length() + 7) // 8)
            if 'metadata-nibble' in self.faults:
                nbytes += 1
            bits.write(nbytes, 2)
            bits.write(v, 8 * nbytes)
        bits.align()
        bits.raw(payload)

    def uncompressed(self, payload):
        bits = self.bits
        bits.write(0, 1)
        self.write_length(len(payload))
        bits.write(1, 1)
        bits.align(0xff if 'padding' in self.faults else 0)
        bits.raw(payload)
        self.output += payload

    def write_length(self, mlen):
        v = mlen - 1
        nibbles = max(4, (v.bit_length() + 3) // 4)
        if 'nibble' in self.faults and nibbles < 6:
            nibbles += 1
        self.bits.write(nibbles - 4, 2)
        self.bits.write(v, 4 * nibbles)

    def finish(self, empty_last):
        if empty_last:
            self.bits.write(1, 1)
            self.bits.write(1, 1)
        self.bits.align(0x7f if 'final-padding' in self.faults else 0)
        return self.bits.bytes()

    def compressed(self, mlen, last, style):
        rng = self.rng
        bits = self.bits
        faults = self.faults
        types = list(style['types']) if 'types' in style else [rng.choice([1, 1, 1, 2, 3, 5, 17]) for _ in range(3)]
        npostfix = style.get('npostfix', rng.randrange(4))
        ndirect = style.get('ndirect', rng.randrange(16)) << npostfix
        modes = [style.get('mode', rng.randrange(4)) for _ in range(types[0])]
        trees_l = style.get('trees_l', rng.choice([1, 1, 2, 3, 6]))
        trees_d = style.get('trees_d', rng.choice([1, 1, 2, 3]))
        cmap_l = self.context_map_values(64 * types[0], trees_l)
        cmap_d = self.context_map_values(4 * types[2], trees_d)
        alphabet = style.get('alphabet') or rng.sample(range(256), rng.choice([1, 2, 3, 4, 5, 16, 60, 256]))

        # Commands, with the output they produce.
        commands = []
        remaining = mlen
        while remaining > 0:
            command = self.command(remaining, alphabet, npostfix, ndirect, style)
            commands.append(command)
            remaining -= command['produced']
        need = [sum(len(c['literals']) for c in commands), len(commands),
                sum(1 for c in commands if c.get('distance') and c['distance'][0] == 'code')]

        # Blocks of each category: (type, count), the first one's type is 0.
        blocks = []
        for category in range(3):
            if types[category] < 2:
                blocks.append([(0, 1 << 24)])
                continue
            plan, total = [], 0
            while total < need[category] or not plan:
                count = rng.choice([1, 1, 2, 3, 5, 8, 20, 100, 700, 17000]) if rng.random() < 0.9 else \
                    rng.randrange(1, 40)
                plan.append((0 if not plan else rng.randrange(types[category]), count))
                total += count
            blocks.append(plan)

        # Events in stream order, and symbol counts per code.
        usage = {}
        events = []
        state = {'block': [0, 0, 0], 'left': [blocks[c][0][1] for c in range(3)], 'ring': [[1, 0] for _ in range(3)]}

        def use(key, symbol):
            usage.setdefault(key, {})
            usage[key][symbol] = usage[key].get(symbol, 0) + 1
            events.append(('symbol', key, symbol))

        def raw(value, count):
            events.append(('bits', value, count))

        def block_count(category, count):
            code, extra = code_for(count, BLOCK_BASE, BLOCK_BITS)
            use(('count', category), code)
            raw(extra, BLOCK_BITS[code])

        def switch(category):
            if state['left'][category] > 0:
                return
            state['block'][category] += 1
            new_type, count = blocks[category][state['block'][category]]
            previous, current = state['ring'][category]
            options = [new_type + 2]
            if new_type == previous:
                options.append(0)
            if new_type == (current + 1) % types[category]:
                options.append(1)
            use(('type', category), rng.choice(options))
            block_count(category, count)
            state['ring'][category] = [current, new_type]
            state['left'][category] = count

        header_counts = []
        for category in range(3):
            if types[category] >= 2:
                code, extra = code_for(blocks[category][0][1], BLOCK_BASE, BLOCK_BITS)
                usage.setdefault(('count', category), {})
                usage[('count', category)][code] = usage[('count', category)].get(code, 0) + 1
                header_counts.append((category, code, extra))

        for command in commands:
            switch(1)
            state['left'][1] -= 1
            use(('command', state['ring'][1][1]), command['symbol'])
            raw(*command['insert_extra'])
            raw(*command['copy_extra'])
            for position in command['literals']:
                switch(0)
                state['left'][0] -= 1
                literal_type = state['ring'][0][1]
                p1 = self.output[position - 1] if position > 0 else 0
                p2 = self.output[position - 2] if position > 1 else 0
                tree = cmap_l[64 * literal_type + context_id(modes[literal_type], p1, p2)]
                use(('literal', tree), self.output[position])
            distance = command.get('distance')
            if distance and distance[0] == 'code':
                switch(2)
                state['left'][2] -= 1
                context = min(command['copy'], 5) - 2
                tree = cmap_d[4 * state['ring'][2][1] + context]
                use(('distance', tree), distance[1])
                raw(distance[2], distance[3])

        # Codes.
        sizes = {'type': lambda c: types[c] + 2, 'count': lambda c: 26, 'literal': lambda t: 256,
                 'command': lambda t: 704, 'distance': lambda t: 16 + ndirect + (48 << npostfix)}
        codes = {}
        fault_key, fault_flags = style.get('fault_code', (None, ()))

        def code(key):
            if key not in codes:
                flags = fault_flags if key == fault_key else ()
                codes[key] = Code(rng, sizes[key[0]](key[1]), usage.get(key, {}), flags)
            return codes[key]

        # Header.
        bits.write(1 if last else 0, 1)
        if last:
            bits.write(0, 1)
        self.write_length(mlen)
        if not last:
            bits.write(0, 1)
        for category in range(3):
            write_count(bits, types[category])
            if types[category] >= 2:
                code(('type', category)).write_header(bits, rng)
                code(('count', category)).write_header(bits, rng)
                _, symbol, extra = next(h for h in header_counts if h[0] == category)
                code(('count', category)).emit(bits, symbol)
                bits.write(extra, BLOCK_BITS[symbol])
        bits.write(npostfix, 2)
        bits.write(ndirect >> npostfix, 4)
        for mode in modes:
            bits.write(mode, 2)
        self.write_context_map(cmap_l, trees_l)
        self.write_context_map(cmap_d, trees_d)
        for tree in range(trees_l):
            code(('literal', tree)).write_header(bits, rng)
        for tree in range(types[1]):
            code(('command', tree)).write_header(bits, rng)
        for tree in range(trees_d):
            code(('distance', tree)).write_header(bits, rng)

        # Data.
        for event in events:
            if event[0] == 'symbol':
                codes[event[1]].emit(bits, event[2])
            else:
                bits.write(event[1], event[2])

    def context_map_values(self, size, trees):
        rng = self.rng
        if trees < 2:
            return [0] * size
        if rng.random() < 0.4:
            values = [0] * size
            for _ in range(rng.randrange(1, 6)):
                start = rng.randrange(size)
                value = rng.randrange(1, trees)
                for i in range(start, min(size, start + rng.randrange(1, 20))):
                    values[i] = value
        else:
            values = [rng.randrange(trees) for _ in range(size)]
        for value, position in zip(range(trees), rng.sample(range(size), min(size, trees))):
            values[position] = value
        return values

    def write_context_map(self, values, trees):
        write_count(self.bits, trees)
        if trees < 2:
            return
        rng = self.rng
        overflow = 'map-overflow' in self.faults
        imtf = rng.random() < 0.5 and not overflow
        coded = mtf(values) if imtf else list(values)
        rle_max = 16 if overflow else rng.choice([0, 0, 1, 2, 3, 4, 6, 16])
        if overflow:
            coded[-4:] = [0, 0, 0, 0]
            self.faults.discard('map-overflow')
        tokens = []
        i = 0
        while i < len(coded):
            if coded[i] != 0:
                tokens.append((coded[i] + rle_max, 0, 0))
                i += 1
                continue
            run = 0
            while i + run < len(coded) and coded[i + run] == 0:
                run += 1
            i += run
            if overflow and i == len(coded):
                run += 1
            while run > 0:
                if rle_max == 0 or run < 2:
                    tokens.append((0, 0, 0))
                    run -= 1
                else:
                    prefix = min(rle_max, run.bit_length() - 1)
                    reps = min(run, (1 << (prefix + 1)) - 1)
                    tokens.append((prefix, reps - (1 << prefix), prefix))
                    run -= reps
        bits = self.bits
        if rle_max == 0:
            bits.write(0, 1)
        else:
            bits.write(1, 1)
            bits.write(rle_max - 1, 4)
        histogram = {}
        for symbol, _, _ in tokens:
            histogram[symbol] = histogram.get(symbol, 0) + 1
        code = Code(rng, trees + rle_max, histogram)
        code.write_header(bits, rng)
        for symbol, extra, count in tokens:
            code.emit(bits, symbol)
            bits.write(extra, count)
        bits.write(1 if imtf else 0, 1)

    def command(self, remaining, alphabet, npostfix, ndirect, style):
        rng = self.rng
        position = len(self.output)
        last_distance = self.ring[3]
        insert = rng.choice([0, 0, 0, 1, 1, 2, 3, 5, 8, 13, 40]) if rng.random() < 0.95 else rng.randrange(0, 2000)
        if position == 0:
            insert = 0 if style.get('dictionary_start') else max(insert, 1)
        insert = min(insert, remaining)
        if 'insert-overflow' in self.faults:
            insert = remaining + 1
            self.faults.discard('insert-overflow')
        literals = []
        for _ in range(min(insert, remaining)):
            literals.append(len(self.output))
            self.output.append(rng.choice(alphabet))
        command = {'literals': literals, 'produced': insert}
        left = remaining - insert
        if left <= 0:
            # The copy is ignored; any copy length and either command form.
            copy = rng.choice([2, 3, 4, 9, 10, 30])
            self.set_symbol(command, insert, copy, rng.random() < 0.5)
            return command

        max_distance = min(len(self.output), self.window)
        kind = rng.choice(['copy', 'copy', 'copy', 'dictionary']) if max_distance else 'dictionary'
        if style.get('dictionary_start') and position == 0:
            kind = 'ring-dictionary'
        if kind == 'copy':
            candidates = [self.short_distance(c) for c in range(16)] + [rng.randrange(1, max_distance + 1)] * 4
            if ndirect:
                candidates.append(rng.randrange(1, ndirect + 1))
            candidates = [d for d in candidates if 1 <= d <= max_distance] or [1]
            distance = rng.choice(candidates)
            forcing = 'short-distance' in self.faults and self.ring[3] > 3
            if forcing:
                distance = 1  # remembered, so that "last distance - 3" is negative next
            copy = min(left, rng.choice([2, 3, 4, 5, 8, 12, 30, 200, 5000]))
            if 'copy-overflow' in self.faults and left < 20000:
                copy = left + 1
                self.faults.discard('copy-overflow')
            if copy < 2:
                return self.retry_as_literals(command, remaining, alphabet)
            options = self.distance_options(distance, npostfix, ndirect, True)
            if forcing:
                options = [o for o in options if o[0] == 'code' and o[1] != 0]
            choice = rng.choice(options)
            source = len(self.output) - distance
            for i in range(min(copy, left)):
                self.output.append(self.output[source + i])
            command['produced'] += min(copy, left)
            code_zero = choice[0] == 'implicit' or choice[1] == 0
            if not code_zero:
                self.remember(distance)
        else:
            if kind == 'ring-dictionary':
                # At the start of the stream the initial last distances point into the dictionary.
                code = rng.randrange(16)
                distance = self.short_distance(code)
                length = rng.randrange(4, 25)
                word_id = distance - max_distance - 1
                transform = word_id >> NDBITS[length]
                index = word_id & ((1 << NDBITS[length]) - 1)
                word = self.ref.word(length, index, transform)
                if len(word) > left:
                    return self.retry_as_literals(command, remaining, alphabet)
                choice = ('implicit',) if code == 0 and rng.random() < 0.5 else ('code', code, 0, 0)
            else:
                for _ in range(50):
                    length = rng.randrange(4, 25)
                    transform = style.get('transform', rng.randrange(121))
                    if callable(transform):
                        transform = transform()
                    index = rng.randrange(1 << NDBITS[length])
                    word = self.ref.word(length, index, transform)
                    if len(word) <= left:
                        break
                else:
                    return self.retry_as_literals(command, remaining, alphabet)
                if 'transform' in self.faults:
                    transform = 121 + rng.randrange(5)
                    self.faults.discard('transform')
                distance = max_distance + 1 + (transform << NDBITS[length]) + index
                if 'word-length' in self.faults:
                    length = rng.choice([2, 3, 25, 30])
                    self.faults.discard('word-length')
                options = self.distance_options(distance, npostfix, ndirect, True)
                choice = rng.choice(options)
            copy = length
            self.output += word
            command['produced'] += len(word)
            self.transforms_used.add(transform)
        if 'short-distance' in self.faults and last_distance <= 3:
            choice = ('code', 8, 0, 0)  # last distance - 3 <= 0
            self.faults.discard('short-distance')
        implicit = choice[0] == 'implicit'
        self.set_symbol(command, insert, copy, implicit)
        if command['implicit'] != implicit:
            choice = ('code', 0, 0, 0)
        command['copy'] = copy
        command['distance'] = ('implicit',) if command['implicit'] else choice
        return command

    def retry_as_literals(self, command, remaining, alphabet):
        # Too little room for a copy: fill the meta-block with literals instead.
        rng = self.rng
        del self.output[len(self.output) - len(command['literals']):]
        literals = []
        for _ in range(remaining):
            literals.append(len(self.output))
            self.output.append(rng.choice(alphabet))
        command = {'literals': literals, 'produced': remaining}
        self.set_symbol(command, remaining, 2, False)
        return command

    @staticmethod
    def set_symbol(command, insert, copy, implicit):
        insert_code, insert_extra = code_for(insert, INSERT_BASE, INSERT_BITS)
        copy_code, copy_extra = code_for(copy, COPY_BASE, COPY_BITS)
        if implicit and insert_code < 8 and copy_code < 16:
            cell = 0 if copy_code < 8 else 1
        else:
            implicit = False
            cell = next(c for c in range(2, 11)
                        if INSERT_RANGE[c] == insert_code & ~7 and COPY_RANGE[c] == copy_code & ~7)
        command['symbol'] = cell * 64 + (insert_code & 7) * 8 + (copy_code & 7)
        command['implicit'] = implicit
        command['insert_extra'] = (insert_extra, INSERT_BITS[insert_code])
        command['copy_extra'] = (copy_extra, COPY_BITS[copy_code])


LUT0 = LUT1 = LUT2 = None


def load_luts():
    """Lut0..2 of RFC 7932 section 7.1, from the Dart source (checked against the RFC's CRC-32 in the tests)."""
    global LUT0, LUT1, LUT2
    text = (ROOT / 'packages/live_net/lib/src/codec/brotli_tables.dart').read_text(encoding='utf-8')
    tables = []
    for name in ('brotliLut0', 'brotliLut1', 'brotliLut2'):
        body = text[text.index(f'const List<int> {name} = ['):]
        body = body[body.index('\n'):body.index('];')]
        body = re.sub(r'//.*', '', body)
        tables.append([int(x) for x in re.findall(r'\d+', body)])
        assert len(tables[-1]) == 256
    LUT0, LUT1, LUT2 = tables


# Groups.

class Group:
    def __init__(self, name, note):
        self.name = name
        self.note = note
        self.data = bytearray()
        self.vectors = []
        self.streams = {}

    def add(self, name, stream, expected):
        assert name not in self.streams, name
        self.vectors.append({'name': name, 'offset': len(self.data), 'size': len(stream), 'expect': expected})
        self.data += stream
        self.streams[name] = stream

    def write(self):
        (OUT / f'{self.name}.bin').write_bytes(self.data)
        manifest = {'note': self.note, 'vectors': self.vectors}
        (OUT / f'{self.name}.json').write_text(json.dumps(manifest, indent=1) + '\n', encoding='utf-8')


OFFICIAL = [
    '10x10y', '64x', 'alice29.txt', 'backward65536', 'compressed_file', 'compressed_repeated', 'cp1251-utf16le',
    'cp852-utf8', 'empty', 'mapsdatazrh', 'monkey', 'quickfox', 'quickfox_repeated', 'random_org_10k.bin',
    'ukkonooa', 'x', 'xyzzy', 'zeros', 'zerosukkanooa',
]


def official_group(testdata):
    group = Group('official', 'google/brotli tests/testdata (MIT licence): <name>.compressed[.NN] decompress to <name>')
    for path in sorted(Path(testdata).iterdir()):
        stem, _, suffix = path.name.partition('.compressed')
        if not path.name.count('.compressed') or stem not in OFFICIAL or path.name == 'empty.compressed.18':
            continue
        original = (Path(testdata) / stem).read_bytes()
        stream = path.read_bytes()
        decoded = Reference.decompress(stream)
        assert decoded == original, path.name
        group.add(path.name, stream, verdict(original))
    return group


def missevan_messages():
    lines = (ROOT / 'fixtures/missevan/danmaku/S06-live/frames.jsonl').read_text(encoding='utf-8').splitlines()
    messages = []
    for line in lines:
        frame = json.loads(line)
        if frame['dir'] == 'in' and 'b64' in frame:
            messages.append(brotli.decompress(base64.b64decode(frame['b64'])[4:]))
    return b'\n'.join(messages)


def reference_group(rng, testdata):
    group = Group('reference', 'inputs compressed by the reference encoder (python3-brotli 1.2.0)')
    alice = (Path(testdata) / 'alice29.txt').read_bytes()
    signal = [int(3000 * math.sin(i / 37) + rng.randrange(-40, 40)) for i in range(2048)]
    block = rng.randbytes(1024)
    inputs = {
        'empty': b'',
        'byte-00': b'\x00',
        'byte-ff': b'\xff',
        'ascii': b'Hello, Brotli! Hello, Brotli! Hello!',
        'text-en': alice[:16384],
        'text-zh': (ROOT / 'docs/E-直播平台/E02-其他国内平台/E02.4-猫耳FM/record.md').read_bytes()[:12288],
        'json-danmaku': missevan_messages(),
        'random': rng.randbytes(2048),
        'repeat-abc': b'abc' * 50000,
        'zeros': bytes(1 << 20),
        'int32-signal': struct.pack(f'<{len(signal)}i', *signal),
        'utf16-text': alice[:6000].decode('latin-1').encode('utf-16-le'),
        'far-repeat': block + alice[40000:46000] + block,
    }
    for name, data in inputs.items():
        for quality in range(12):
            add_compressed(group, f'{name}/q{quality}', data, quality=quality)
    for name in ('text-en', 'far-repeat'):
        data = inputs[name][-4096:]
        for lgwin in range(10, 25):
            for quality in (5, 11):
                add_compressed(group, f'{name}-4k/q{quality}-w{lgwin}', data, quality=quality, lgwin=lgwin)
    for name in ('text-en', 'int32-signal'):
        for mode_name, mode in (('text', brotli.MODE_TEXT), ('font', brotli.MODE_FONT)):
            for quality in (5, 10, 11):
                add_compressed(group, f'{name}/q{quality}-{mode_name}', inputs[name][:16384], quality=quality, mode=mode)
    for lgblock in (16, 18, 24):
        for quality in (5, 11):
            add_compressed(group, f'text-en/q{quality}-b{lgblock}', inputs['text-en'], quality=quality, lgblock=lgblock)
    # Past 16 MiB, with a repeat just inside and just outside the largest window (2^24 - 16).
    window = (1 << 24) - 16
    head = rng.randbytes(2048)
    for name, gap in (('16m-inside', window - 2048 - 64), ('16m-outside', window - 2048 + 64)):
        data = head + bytes(gap) + head + b'end'
        add_compressed(group, f'{name}/q5-w24', data, quality=5, lgwin=24)
    return group


def add_compressed(group, name, data, **params):
    stream = brotli.compress(data, **params)
    assert brotli.decompress(stream) == data, name
    group.add(name, stream, verdict(data))


def crafted_group(reference, rng):
    group = Group('crafted', 'streams written by tools/brotli/gen_test_vectors.py (Crafter), checked with the '
                             'reference decoder')
    checked = 0

    def craft(name, build, wbits=None, faults=(), check=None):
        nonlocal checked
        for _ in range(100):
            crafter = Crafter(reference, rng, wbits or rng.choice(range(10, 25)), faults)
            empty_last = build(crafter)
            if check is None or check(crafter):
                break
        else:
            raise SystemExit(f'{name}: could not reach the feature')
        stream = crafter.finish(empty_last)
        if name.startswith('bad/') and 'trailing' in faults:
            stream += b'\x00'
        decoded = Reference.decompress(stream)
        if name.startswith('bad/'):
            if decoded is not None:
                raise SystemExit(f'{name}: the reference decoder accepts it')
            group.add(name, stream, 'error')
            return
        if decoded != bytes(crafter.output):
            model = bytes(crafter.output)
            first = next((i for i in range(min(len(model), len(decoded or b''))) if model[i] != decoded[i]), None)
            debug = os.environ.get('BROTLI_DEBUG_DIR')
            if debug:
                debug = Path(debug)
                (debug / 'failed.br').write_bytes(stream)
                (debug / 'failed.model').write_bytes(model)
            raise SystemExit(f'{name}: model and reference decoder disagree (model {len(model)}, reference '
                             f'{None if decoded is None else len(decoded)}, first difference {first})')
        checked += 1
        group.add(name, stream, verdict(decoded))

    def one_metablock(mlen, style=None):
        def build(c):
            c.compressed(mlen, True, style or {})
            return False
        return build

    def mixed(c):
        for _ in range(rng.randrange(1, 5)):
            kind = rng.choice(['compressed', 'compressed', 'uncompressed', 'metadata'])
            if kind == 'compressed':
                c.compressed(rng.randrange(1, 1500), False, {})
            elif kind == 'uncompressed':
                c.uncompressed(rng.randbytes(rng.randrange(1, 200)))
            else:
                c.metadata(False, rng.randbytes(rng.choice([0, 1, 5, 300])))
        ending = rng.choice(['empty', 'compressed', 'metadata'])
        if ending == 'compressed':
            c.compressed(rng.randrange(1, 1500), True, {})
        elif ending == 'metadata':
            c.metadata(True, rng.randbytes(rng.randrange(0, 20)))
        return ending == 'empty'

    for wbits in range(10, 25):
        craft(f'window/w{wbits}', mixed, wbits)
    for mode, name in enumerate(['lsb6', 'msb6', 'utf8', 'signed']):
        for i in range(6):
            craft(f'context/{name}-{i}', one_metablock(rng.randrange(200, 3000), {
                'mode': mode, 'types': (rng.choice([1, 2, 3]), 1, 1), 'trees_l': rng.choice([2, 4, 9, 64]),
                'alphabet': list(range(256)) if i % 2 else rng.sample(range(256), 30)}))
    for i in range(12):
        craft(f'blocks/{i}', one_metablock(rng.randrange(500, 5000), {
            'types': (rng.choice([2, 3, 7, 40]), rng.choice([2, 3, 7, 256]), rng.choice([2, 3, 9]))}))
    for postfix in range(4):
        for direct in (0, 1, 7, 15):
            craft(f'distance/p{postfix}-d{direct}', one_metablock(rng.randrange(1000, 6000), {
                'npostfix': postfix, 'ndirect': direct}))
    for transform in range(121):
        craft(f'transform/{transform}', one_metablock(rng.randrange(100, 400), {'transform': transform}),
              check=lambda c, t=transform: t in c.transforms_used)
    for i in range(8):
        craft(f'dictionary-start/{i}', one_metablock(rng.randrange(30, 300), {'dictionary_start': True}))
    for i in range(40):
        craft(f'random/{i}', mixed)
    craft('uncompressed-only', lambda c: (c.uncompressed(rng.randbytes(3000)), True)[-1])

    # Invalid: one per check. Built like the valid ones, with one fault.
    def fault(name, faults, build=None, wbits=None):
        craft(f'bad/{name}', build or one_metablock(rng.randrange(300, 2000)), wbits, faults)

    fault('reserved-bit', {'reserved'}, lambda c: (c.metadata(False, b'abc'), True)[-1])
    fault('metadata-nibble', {'metadata-nibble'}, lambda c: (c.metadata(False, b'x' * 5), True)[-1])
    fault('mlen-nibble', {'nibble'})
    fault('padding-before-uncompressed', {'padding'}, lambda c: (c.uncompressed(b'hello'), True)[-1])
    fault('final-padding', {'final-padding'}, lambda c: (c.uncompressed(b'hello'), True)[-1])
    fault('trailing-byte', {'trailing'})
    literal0 = ('literal', 0)
    fault('duplicate-symbol', set(), one_metablock(500, {'fault_code': (literal0, ('simple', 'duplicate-symbol')),
                                                         'alphabet': [65, 66, 67]}))
    fault('symbol-out-of-range', set(), one_metablock(500, {'types': (3, 1, 1),
                                                            'fault_code': (('type', 0), ('simple', 'symbol-range'))}))
    fault('incomplete-code', set(), one_metablock(500, {'fault_code': (literal0, ('complex', 'incomplete')),
                                                        'alphabet': list(range(40))}))
    fault('code-length-code-space', set(), one_metablock(500, {'fault_code': (literal0, ('complex', 'cl-space')),
                                                               'alphabet': list(range(40))}))
    fault('code-lengths-overflow', set(), one_metablock(500, {
        'fault_code': (literal0, ('complex', 'lengths-overflow')), 'alphabet': list(range(250, 256))}))
    fault('context-map-overflow', {'map-overflow'}, one_metablock(500, {'trees_l': 3}))
    fault('transform-out-of-range', {'transform'}, one_metablock(3000, {}))
    fault('word-length', {'word-length'}, one_metablock(3000, {}))
    fault('short-distance', {'short-distance'}, one_metablock(3000, {}))
    fault('copy-overflow', {'copy-overflow'}, one_metablock(3000, {}))
    fault('insert-overflow', {'insert-overflow'}, one_metablock(3000, {}))
    print(f'crafted: {checked} valid streams match the model')
    return group


def mutations(rng, groups):
    """Damaged copies of small valid streams, with the reference decoder's verdict."""
    cases = []
    bases = []
    for group in groups:
        for vector in group.vectors:
            if vector['expect'] != 'error' and 1 <= vector['size'] <= 4096:
                bases.append((group.name, vector['name'], group.streams[vector['name']]))
    rng.shuffle(bases)
    bases = sorted(bases[:60], key=lambda b: (b[0], b[1]))
    for group_name, name, stream in bases:
        base = f'{group_name}/{name}'
        cuts = range(len(stream)) if len(stream) <= 16 else sorted(rng.sample(range(len(stream)), 12))
        for cut in cuts:
            cases.append({'base': base, 'truncate': cut, 'expect': verdict(Reference.decompress(stream[:cut]))})
        for _ in range(24):
            flips = sorted(rng.sample(range(len(stream) * 8), rng.choice([1, 1, 1, 2, 3])))
            damaged = bytearray(stream)
            for bit in flips:
                damaged[bit >> 3] ^= 1 << (bit & 7)
            cases.append({'base': base, 'flip': flips, 'expect': verdict(Reference.decompress(bytes(damaged)))})
        for extra in ('00', '03', 'ff00'):
            appended = stream + bytes.fromhex(extra)
            cases.append({'base': base, 'append': extra, 'expect': verdict(Reference.decompress(appended))})
    window_patterns = ['0', '0011', '0101', '0111', '1001', '1011', '1101', '1111', '0000001', '0100001', '0110001',
                       '1000001', '1010001', '1100001', '1110001', '0010001', '0001001', '0000011']
    for group_name, name, stream in bases[::5]:
        drop = window_length(stream)
        for pattern in window_patterns:
            patched = rewindow(stream, drop, pattern)
            cases.append({'base': f'{group_name}/{name}', 'window': pattern,
                          'expect': verdict(Reference.decompress(patched))})
    return cases


def window_length(stream):
    """Bits of the WBITS field at the start of `stream`."""
    first = stream[0]
    if first & 1 == 0:
        return 1
    return 4 if (first >> 1) & 7 else 7


def rewindow(stream, drop, pattern):
    """`stream` with its WBITS field replaced by `pattern` (bits in stream order, as in RFC 7932 read right to
    left, i.e. the pattern string reversed)."""
    bits = [(stream[i >> 3] >> (i & 7)) & 1 for i in range(len(stream) * 8)]
    new = [int(c) for c in reversed(pattern)] + bits[drop:]
    new += [0] * (-len(new) % 8)
    return bytes(sum(new[i + k] << k for k in range(8)) for i in range(0, len(new), 8))


def transform_hashes(reference):
    hashes = {}
    for length in range(4, 25):
        digest = hashlib.sha256()
        for index in range(1 << NDBITS[length]):
            for transform in range(121):
                digest.update(reference.word(length, index, transform))
        hashes[str(length)] = digest.hexdigest()
    return {'note': 'SHA-256 per word length of transforms 0..120 of every word, in word order, from libbrotlicommon',
            'sha256': hashes}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--official', required=True, help="google/brotli's tests/testdata directory")
    args = parser.parse_args()

    load_luts()
    reference = Reference()
    OUT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED)
    groups = [official_group(args.official), reference_group(rng, args.official), crafted_group(reference, rng)]
    for group in groups:
        group.write()
    cases = mutations(rng, groups)
    note = json.dumps('operations on <group>/<name>; window patterns are written as in RFC 7932 (read right to left)')
    lines = ',\n'.join(json.dumps(case, separators=(',', ':')) for case in cases)
    (OUT / 'mutations.json').write_text(f'{{"note":{note},"cases":[\n{lines}\n]}}\n', encoding='utf-8')
    (OUT / 'transforms.json').write_text(json.dumps(transform_hashes(reference), indent=1) + '\n', encoding='utf-8')
    total = sum(p.stat().st_size for p in OUT.iterdir())
    errors = sum(1 for c in cases if c['expect'] == 'error')
    print(f'{sum(len(g.vectors) for g in groups)} streams, {len(cases)} mutations ({errors} rejected), '
          f'{total} bytes in {OUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
