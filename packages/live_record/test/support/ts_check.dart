import 'dart:typed_data';

/// What a structural pass over an MPEG-TS file found: units per PID, and
/// every way a unit could be cut.
final class TsCheck {
  new _();

  /// Parses [data] (whole 188-byte packets).
  factory of(Uint8List data) {
    final check = TsCheck._();
    if (data.length % 188 != 0) check.problems.add('length ${data.length} is not whole packets');
    final counters = <int, int>{};
    final open = <int, ({int offset, int declared, int received})>{};
    for (var at = 0; at + 188 <= data.length; at += 188) {
      final index = at ~/ 188;
      if (data[at] != 0x47) {
        check.problems.add('no sync at $at');
        return check;
      }
      final start = (data[at + 1] & 0x40) != 0;
      final pid = ((data[at + 1] & 0x1F) << 8) | data[at + 2];
      final control = (data[at + 3] >> 4) & 0x03;
      final counter = data[at + 3] & 0x0F;
      check.pids.add(pid);
      if (index < 3) check.firstPids.add(pid);
      if (pid == 0x1FFF) continue;
      var payload = at + 4;
      if (control == 2 || control == 3) payload = at + 5 + data[at + 4];
      final hasPayload = (control == 1 || control == 3) && payload < at + 188;
      if (!hasPayload) continue;
      final last = counters[pid];
      counters[pid] = counter;
      if (last != null && counter != (last + 1) & 0x0F && !start) {
        check.problems.add('continuity $last → $counter inside a unit of PID $pid at packet $index');
      }
      if (pid == 0) {
        if (start) check.pats.add(index);
        continue;
      }
      if (pid == 0x1000) continue;
      if (start) {
        final previous = open.remove(pid);
        if (previous != null && previous.declared > 0 && previous.received != previous.declared) {
          check.problems.add('PES of PID $pid at ${previous.offset}: ${previous.received} of ${previous.declared}');
        }
        if (data[payload] != 0 || data[payload + 1] != 0 || data[payload + 2] != 1) {
          check.problems.add('no PES start at packet $index');
          continue;
        }
        final declared = (data[payload + 4] << 8) | data[payload + 5];
        open[pid] = (offset: index, declared: declared, received: at + 188 - payload - 6);
        final streamId = data[payload + 3];
        if ((streamId & 0xF0) == 0xE0) {
          check.videoStarts.add(index);
          final flags = data[payload + 7] >> 6;
          final pts = flags >= 2 ? _timestamp(data, payload + 9) : -index;
          check
            ..videoPts.add(pts)
            .._videoPid = pid;
          check.videoPesPackets[pts] = 1;
          if (_isIdr(data, payload + 9 + data[payload + 8], at + 188)) check.keyStarts.add(index);
        } else if ((streamId & 0xE0) == 0xC0) {
          check.audioStarts.add(index);
        }
      } else {
        final unit = open[pid];
        if (unit == null) {
          check.orphans++;
          continue;
        }
        if (pid == check._videoPid) {
          check.videoPesPackets[check.videoPts.last] = check.videoPesPackets[check.videoPts.last]! + 1;
        }
        open[pid] = (offset: unit.offset, declared: unit.declared, received: unit.received + at + 188 - payload);
      }
    }
    for (final MapEntry(key: pid, value: unit) in open.entries) {
      if (unit.declared > 0 && unit.received != unit.declared) {
        check.problems.add('last PES of PID $pid at ${unit.offset}: ${unit.received} of ${unit.declared}');
      }
    }
    return check;
  }

  /// Whether the payload from [from] holds an IDR slice NAL before [to].
  static bool _isIdr(Uint8List data, int from, int to) {
    for (var i = from; i + 3 < to; i++) {
      if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1 && (data[i + 3] & 0x1F) == 5) return true;
    }
    // The IDR slice may start in a later packet: a keyframe AU carries an SPS first.
    for (var i = from; i + 3 < to; i++) {
      if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1 && (data[i + 3] & 0x1F) == 7) return true;
    }
    return false;
  }

  static int _timestamp(Uint8List data, int at) =>
      ((data[at] >> 1) & 0x07) * (1 << 30) +
      (data[at + 1] << 22) +
      ((data[at + 2] >> 1) << 15) +
      (data[at + 3] << 7) +
      (data[at + 4] >> 1);

  /// Cut units, lost continuity inside a unit, lost sync.
  final List<String> problems = [];
  final Set<int> pids = {};

  /// PIDs of the first three packets.
  final List<int> firstPids = [];

  /// Packet indices of PATs, video PES starts, keyframe PES starts, audio PES starts.
  final List<int> pats = [];
  final List<int> videoStarts = [];
  final List<int> keyStarts = [];
  final List<int> audioStarts = [];

  /// Raw PTS of the video PES, in order.
  final List<int> videoPts = [];

  /// Packets of each video PES, by PTS.
  final Map<int, int> videoPesPackets = {};
  int? _videoPid;

  /// Packets of a PID before its first PES start.
  int orphans = 0;
}
