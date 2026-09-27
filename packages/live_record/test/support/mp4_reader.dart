import 'dart:typed_data';

/// One ISO BMFF box of a parsed file.
final class Box {
  /// Creates a box.
  new(this.type, this.offset, this.size, this.headerSize, this.children);

  /// Four-character type.
  final String type;

  /// Offset of the box in the file.
  final int offset;

  /// Box size including the header.
  final int size;

  /// 8, or 16 with a 64-bit size.
  final int headerSize;

  /// Child boxes (containers and sample entries only).
  final List<Box> children;

  /// The first child of [type] along [path] (`'trak/mdia/minf'`), or null.
  Box? find(String path) {
    Box? box = this;
    for (final part in path.split('/')) {
      box = box?.children.where((child) => child.type == part).firstOrNull;
    }
    return box;
  }

  /// Every child of [type].
  List<Box> all(String type) => [
    for (final child in children)
      if (child.type == type) child,
  ];
}

const _containers = {'moov', 'trak', 'mdia', 'minf', 'stbl', 'dinf', 'edts', 'udta'};

/// Parses the box tree of [bytes] (a whole file); throws [FormatException]
/// when a box overruns its parent.
List<Box> parseBoxes(Uint8List bytes, [int start = 0, int? end]) {
  final data = ByteData.sublistView(bytes);
  final limit = end ?? bytes.length;
  final boxes = <Box>[];
  var offset = start;
  while (offset + 8 <= limit) {
    var size = data.getUint32(offset);
    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    var header = 8;
    if (size == 1) {
      size = data.getUint32(offset + 8) * 0x100000000 + data.getUint32(offset + 12);
      header = 16;
    } else if (size == 0) {
      size = limit - offset;
    }
    if (size < header || offset + size > limit) throw FormatException('box $type at $offset overruns ($size)');
    var children = const <Box>[];
    if (_containers.contains(type)) {
      children = parseBoxes(bytes, offset + header, offset + size);
    } else if (type == 'stsd') {
      children = parseBoxes(bytes, offset + 16, offset + size);
    } else if (type == 'avc1' || type == 'hvc1') {
      children = parseBoxes(bytes, offset + 8 + 78, offset + size);
    } else if (type == 'mp4a') {
      children = parseBoxes(bytes, offset + 8 + 28, offset + size);
    }
    boxes.add(Box(type, offset, size, header, children));
    offset += size;
  }
  if (offset != limit) throw FormatException('${limit - offset} stray bytes at $offset');
  return boxes;
}

/// Sample tables of one track, decoded.
final class TrackSamples {
  /// Creates the tables.
  new({
    required this.handler,
    required this.timescale,
    required this.sizes,
    required this.decodeTimes,
    required this.offsets,
    required this.compositionOffsets,
    required this.syncSamples,
    required this.sampleOffsets,
    required this.entry,
    required this.edits,
    required this.cttsVersion,
  });

  /// `vide` or `soun`.
  final String handler;

  /// Media timescale.
  final int timescale;

  /// Sample sizes.
  final List<int> sizes;

  /// Decode time of every sample (and the end time as the last element).
  final List<int> decodeTimes;

  /// Chunk offsets.
  final List<int> offsets;

  /// Composition offset per sample.
  final List<int> compositionOffsets;

  /// 1-based sync sample numbers; null without `stss` (all samples are sync).
  final List<int>? syncSamples;

  /// File offset of every sample.
  final List<int> sampleOffsets;

  /// Sample entry type (`avc1`, `hvc1`, `mp4a`).
  final String entry;

  /// `elst` entries as (duration, media time); empty without `edts`.
  final List<(int, int)> edits;

  /// `ctts` version, or null without `ctts`.
  final int? cttsVersion;

  /// Payload of sample [index] from the file [bytes].
  Uint8List sample(Uint8List bytes, int index) =>
      Uint8List.sublistView(bytes, sampleOffsets[index], sampleOffsets[index] + sizes[index]);
}

/// Decodes the sample tables of [trak] in the file [bytes].
TrackSamples readTrack(Uint8List bytes, Box trak) {
  final data = ByteData.sublistView(bytes);
  int u32(int at) => data.getUint32(at);
  int u64(int at) => data.getUint32(at) * 0x100000000 + data.getUint32(at + 4);
  final stbl = trak.find('mdia/minf/stbl')!;
  final mdhd = trak.find('mdia/mdhd')!;
  final mdhdV1 = bytes[mdhd.offset + 8] == 1;
  final timescale = u32(mdhd.offset + 12 + (mdhdV1 ? 16 : 8));
  final handler = String.fromCharCodes(bytes, trak.find('mdia/hdlr')!.offset + 16, trak.find('mdia/hdlr')!.offset + 20);

  final stsz = stbl.find('stsz')!;
  final constant = u32(stsz.offset + 12);
  final count = u32(stsz.offset + 16);
  final sizes = constant != 0
      ? List<int>.filled(count, constant)
      : [for (var i = 0; i < count; i++) u32(stsz.offset + 20 + 4 * i)];

  final stts = stbl.find('stts')!;
  final times = <int>[0];
  for (var i = 0; i < u32(stts.offset + 12); i++) {
    final runCount = u32(stts.offset + 16 + 8 * i);
    final delta = u32(stts.offset + 20 + 8 * i);
    for (var j = 0; j < runCount; j++) {
      times.add(times.last + delta);
    }
  }

  final ctts = stbl.find('ctts');
  final composition = List<int>.filled(count, 0);
  int? cttsVersion;
  if (ctts != null) {
    cttsVersion = bytes[ctts.offset + 8];
    var index = 0;
    for (var i = 0; i < u32(ctts.offset + 12); i++) {
      final runCount = u32(ctts.offset + 16 + 8 * i);
      final value = data.getInt32(ctts.offset + 20 + 8 * i);
      for (var j = 0; j < runCount; j++) {
        composition[index++] = value;
      }
    }
  }

  final stss = stbl.find('stss');
  final sync = stss == null ? null : [for (var i = 0; i < u32(stss.offset + 12); i++) u32(stss.offset + 16 + 4 * i)];

  final stco = stbl.find('stco');
  final co64 = stbl.find('co64');
  final offsets = stco != null
      ? [for (var i = 0; i < u32(stco.offset + 12); i++) u32(stco.offset + 16 + 4 * i)]
      : [for (var i = 0; i < u32(co64!.offset + 12); i++) u64(co64.offset + 16 + 8 * i)];

  final stsc = stbl.find('stsc')!;
  final runs = [
    for (var i = 0; i < u32(stsc.offset + 12); i++) (u32(stsc.offset + 16 + 12 * i), u32(stsc.offset + 20 + 12 * i)),
  ];
  final sampleOffsets = <int>[];
  var sample = 0;
  for (var chunk = 1; chunk <= offsets.length; chunk++) {
    var perChunk = 0;
    for (final (first, samples) in runs) {
      if (first <= chunk) perChunk = samples;
    }
    var at = offsets[chunk - 1];
    for (var i = 0; i < perChunk; i++) {
      sampleOffsets.add(at);
      at += sizes[sample++];
    }
  }

  final edits = <(int, int)>[];
  final elst = trak.find('edts/elst');
  if (elst != null) {
    final v1 = bytes[elst.offset + 8] == 1;
    var at = elst.offset + 16;
    for (var i = 0; i < u32(elst.offset + 12); i++) {
      if (v1) {
        edits.add((u64(at), data.getInt64(at + 8)));
        at += 20;
      } else {
        edits.add((u32(at), data.getInt32(at + 4)));
        at += 12;
      }
    }
  }

  return TrackSamples(
    handler: handler,
    timescale: timescale,
    sizes: sizes,
    decodeTimes: times,
    offsets: offsets,
    compositionOffsets: composition,
    syncSamples: sync,
    sampleOffsets: sampleOffsets,
    entry: stbl.find('stsd')!.children.first.type,
    edits: edits,
    cttsVersion: cttsVersion,
  );
}
