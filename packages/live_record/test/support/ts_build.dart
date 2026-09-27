import 'dart:typed_data';

Uint8List _hex(String text) =>
    Uint8List.fromList([for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)]);

/// Constants of the synthetic MPEG-TS streams.
abstract final class TsBuild {
  static const pmtPid = 0x1000;
  static const videoPid = 0x100;
  static const audioPid = 0x101;

  /// SPS and PPS of the x264 fixture (High, 160×96).
  static final Uint8List sps = _hex('6764000bacd9428db0110000030001000003003c0f142996');
  static final Uint8List pps = _hex('68ebe3cb22c0');

  /// The same SPS at another level: a different configuration.
  static final Uint8List otherSps = _hex('6764000dacd9428db0110000030001000003003c0f142996');
}

/// One access unit of a synthetic stream.
final class TsUnit {
  /// An H.264 access unit: AUD, SPS and PPS on keyframes, one slice of
  /// [size] bytes. With [tail] its last [tail] bytes start the next video
  /// PES instead (Twitch / Amazon IVS muxing).
  new video({required this.pts, int? dts, this.key = false, this.size = 20, Uint8List? sps, this.tail = 0})
    : video = true,
      dts = dts ?? pts,
      frames = 1,
      splitLast = false,
      declaredExtra = 0,
      sps = sps ?? TsBuild.sps;

  /// [frames] ADTS frames (48 kHz AAC-LC mono) of [size] bytes each; with
  /// [splitLast] the last frame continues in the next audio unit.
  new audio({required this.pts, this.frames = 1, this.size = 30, this.splitLast = false, this.declaredExtra = 0})
    : video = false,
      dts = pts,
      key = true,
      tail = 0,
      sps = TsBuild.sps;

  final bool video;
  final int tail;
  final int pts;
  final int dts;
  final bool key;
  final int size;
  final int frames;
  final bool splitLast;
  final int declaredExtra;
  final Uint8List sps;
}

/// One ADTS frame of [length] bytes in total (48 kHz, AAC-LC, mono).
Uint8List adtsFrame(int length, {int fill = 0x21}) {
  final frame = Uint8List(length)
    ..fillRange(7, length, fill)
    ..[0] = 0xFF
    ..[1] = 0xF1
    ..[2] = (1 << 6) | (3 << 2)
    ..[3] = (1 << 6) | ((length >> 11) & 0x03)
    ..[4] = (length >> 3) & 0xFF
    ..[5] = ((length & 0x07) << 5) | 0x1F
    ..[6] = 0xFC;
  return frame;
}

Uint8List _timestamp(int prefix, int value) => Uint8List.fromList([
  (prefix << 4) | (((value >> 30) & 0x07) << 1) | 1,
  (value >> 22) & 0xFF,
  (((value >> 15) & 0x7F) << 1) | 1,
  (value >> 7) & 0xFF,
  ((value & 0x7F) << 1) | 1,
]);

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte << 24;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x80000000) != 0 ? ((crc << 1) ^ 0x04C11DB7) : crc << 1;
      crc &= 0xFFFFFFFF;
    }
  }
  return crc;
}

/// A synthetic MPEG-TS stream: PAT, PMT, then [units] as PES packets.
Uint8List buildTs(List<TsUnit> units, {int audioType = 0x0F, int videoType = 0x1B}) {
  final out = BytesBuilder();
  final counters = <int, int>{};

  void packets(int pid, Uint8List payload, {bool psi = false}) {
    var at = 0;
    var first = true;
    while (at < payload.length || first) {
      final packet = Uint8List(188)..[0] = 0x47;
      final counter = counters[pid] ?? 0;
      counters[pid] = (counter + 1) & 0x0F;
      packet
        ..[1] = (first ? 0x40 : 0) | (pid >> 8)
        ..[2] = pid & 0xFF;
      const room = 184;
      final left = payload.length - at;
      if (left >= room || psi) {
        packet[3] = 0x10 | counter;
        final take = left < room ? left : room;
        packet.setRange(4, 4 + take, payload, at);
        if (take < room) packet.fillRange(4 + take, 188, 0xFF);
        at += take;
      } else {
        // Adaptation field stuffing so the payload ends the packet.
        final stuffing = room - left;
        packet[3] = 0x30 | counter;
        packet[4] = stuffing - 1;
        if (stuffing > 1) {
          packet[5] = 0;
          packet.fillRange(6, 4 + stuffing, 0xFF);
        }
        packet.setRange(4 + stuffing, 188, payload, at);
        at += left;
      }
      first = false;
      out.add(packet);
    }
  }

  Uint8List section(List<int> body) {
    final crc = _crc32(body);
    return Uint8List.fromList([0, ...body, crc >> 24, (crc >> 16) & 0xFF, (crc >> 8) & 0xFF, crc & 0xFF]);
  }

  final patBody = [
    0x00,
    0xB0,
    13,
    0x00,
    0x01,
    0xC1,
    0x00,
    0x00,
    0x00,
    0x01,
    0xE0 | (TsBuild.pmtPid >> 8),
    TsBuild.pmtPid & 0xFF,
  ];
  packets(0, section(patBody), psi: true);
  final streams = [
    videoType,
    0xE0 | (TsBuild.videoPid >> 8),
    TsBuild.videoPid & 0xFF,
    0xF0,
    0x00,
    audioType,
    0xE0 | (TsBuild.audioPid >> 8),
    TsBuild.audioPid & 0xFF,
    0xF0,
    0x00,
  ];
  final pmtBody = [
    0x02,
    0xB0,
    13 + streams.length,
    0x00,
    0x01,
    0xC1,
    0x00,
    0x00,
    0xE0 | (TsBuild.videoPid >> 8),
    TsBuild.videoPid & 0xFF,
    0xF0,
    0x00,
    ...streams,
  ];
  packets(TsBuild.pmtPid, section(pmtBody), psi: true);

  Uint8List? carry;
  Uint8List? videoTail;
  var serial = 0;
  for (final unit in units) {
    final payload = BytesBuilder();
    if (unit.video) {
      if (videoTail != null) payload.add(videoTail);
      videoTail = null;
      void nal(List<int> bytes) => payload
        ..add(const [0, 0, 0, 1])
        ..add(bytes);
      nal(const [0x09, 0xF0]);
      if (unit.key) {
        nal(unit.sps);
        nal(TsBuild.pps);
      }
      final slice = Uint8List(unit.size)
        ..[0] = unit.key ? 0x65 : 0x41
        ..fillRange(1, unit.size, 0x80 + (serial++ & 0x3F));
      nal(slice);
      if (unit.tail > 0) {
        final all = payload.takeBytes();
        payload.add(all.sublist(0, all.length - unit.tail));
        videoTail = all.sublist(all.length - unit.tail);
      }
    } else {
      if (carry != null) payload.add(carry);
      carry = null;
      for (var i = 0; i < unit.frames; i++) {
        final frame = adtsFrame(unit.size, fill: 0x20 + (serial++ & 0x3F));
        if (unit.splitLast && i == unit.frames - 1) {
          payload.add(frame.sublist(0, unit.size ~/ 2));
          carry = frame.sublist(unit.size ~/ 2);
        } else {
          payload.add(frame);
        }
      }
    }
    final data = payload.takeBytes();
    final both = unit.dts != unit.pts;
    final header = [
      0x80,
      if (both) 0xC0 else 0x80,
      if (both) 10 else 5,
      ..._timestamp(both ? 3 : 2, unit.pts),
      if (both) ..._timestamp(1, unit.dts),
    ];
    final length = unit.video ? 0 : header.length + data.length + unit.declaredExtra;
    final pes = Uint8List.fromList([
      0,
      0,
      1,
      if (unit.video) 0xE0 else 0xC0,
      length >> 8,
      length & 0xFF,
      ...header,
      ...data,
    ]);
    packets(unit.video ? TsBuild.videoPid : TsBuild.audioPid, pes);
  }
  return out.takeBytes();
}
