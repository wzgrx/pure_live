import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_record/src/errors.dart';
import 'package:live_record/src/gaps.dart';
import 'package:live_record/src/hls/feed.dart';
import 'package:live_record/src/remux/ts_demux.dart';
import 'package:live_record/src/ts/stream_source.dart';

/// What a continuous MPEG-TS stream remembers across the connections of a
/// session (spec §8.3): where its timeline stood, for the gap estimate.
final class TsStreamState {
  /// Raw 33-bit time (90 kHz) of the last media unit written; null before the first.
  int? lastTime;

  /// Usual step between media units (90 kHz); one frame.
  int step = 3600;

  /// Whether media went into the current writer.
  bool wroteMedia = false;

  /// Forgets the timeline: another writer took over.
  void reset() {
    lastTime = null;
    wroteMedia = false;
  }
}

/// Where a continuous MPEG-TS feed writes: the session's `.ts` writer.
abstract interface class TsSink {
  /// Completes when the writer can take more (backpressure, §6.8).
  Future<void> get ready;

  /// Whether a keyframe with [signature] starts a new file: no `.ts` file
  /// yet, another codec setup, or a split limit reached (§6.5).
  bool wantsFile(TsSignature signature);

  /// Closes the current file and opens the next for [signature].
  void startFile(TsSignature signature);

  /// A keyframe with [signature] continues the current file.
  void noteSignature(TsSignature signature);

  /// Appends whole packets holding [units] media units that last [durationMs].
  void addPackets(Uint8List packets, {int durationMs = 0, int units = 0});

  /// Records missing media at the current position.
  void addMissing(HlsMissing missing);
}

/// Limits of a continuous MPEG-TS feed.
final class TsTimings {
  /// Creates the limits.
  const new({this.keyframeWait = const Duration(seconds: 30), this.raiFallback = 300});

  /// Longest wait for a keyframe at the start of a connection or after a
  /// cut; then the connection ends (as `unsupportedProtocol` when it wrote
  /// nothing: scrambled or unreadable content).
  final Duration keyframeWait;

  /// Video units of a codec the feed cannot parse after which, without any
  /// `random_access_indicator`, every unit counts as a keyframe.
  final int raiFallback;
}

enum _Kind { psi, video, es }

/// One PES packet or PSI section of a tracked PID.
final class _Unit {
  new(this.pid, this.kind, this.serial, {required this.primary});

  final int pid;
  final _Kind kind;
  final int serial;
  final bool primary;

  bool complete = false;
  bool dropped = false;

  /// PES: bytes the header declares after its first 6; PSI: section bytes. Null: until the next start.
  int? declared;

  /// Bytes received towards [declared] (PES after the first 6 bytes; PSI section bytes).
  int received = 0;

  /// Video PES, PSI section: the bytes so far (for classification).
  BytesBuilder? body;

  /// PSI: the packets, for the copies in front of a file.
  List<Uint8List>? packets;

  /// Raw DTS (or PTS) of a PES, 90 kHz.
  int? time;

  /// Whether a new file or a resumed stream can start here.
  bool key = false;

  /// `random_access_indicator` of the first packet.
  bool rai = false;

  /// Parameter sets of an H.264 / H.265 keyframe.
  Uint8List? sets;
}

final class _Packet {
  new(this.bytes, this.unit, {this.first = false});

  final Uint8List bytes;

  /// The unit it belongs to; null for packets that never wait (other PIDs,
  /// null packets) and for orphans ([drop]).
  final _Unit? unit;

  /// Whether it starts [unit].
  final bool first;

  bool drop = false;
}

/// Records one connection of a continuous MPEG-TS stream (spec §8.2): the
/// 188-byte packets go to the writer in the order they arrived, and every
/// PES and PSI section of the program is written whole or not at all.
///
/// A unit waits until it is complete (a video PES until the next one
/// starts, a PES with a declared length until it is full), so writing lags
/// reading by about a frame. The stream starts at the first video keyframe
/// (audio-only programs: the first audio PES), after a copy of the last
/// PAT and PMT; the other streams start at their next PES. When the
/// connection ends, units not yet complete are dropped. Lost packets or
/// sync on the video (a `damaged` gap) and a changed program or AAC
/// configuration cut the same way and wait for the next keyframe; lost
/// packets of another stream drop only that PES. A new file starts at a
/// keyframe when the writer wants one (codec change, split); PES of other
/// streams begun before it end in the old file.
///
/// Timestamps are not rewritten; the file time follows DTS (audio-only:
/// PTS), a gap after a reconnection is recorded at the first keyframe.
final class TsFeed {
  /// Creates a feed reading `source` into `sink`; `head` are bytes already
  /// read from it (the sniff). A connection after one lost at [lostAt] for
  /// [reason] records the gap.
  new({
    required this._source,
    required this._sink,
    required this.state,
    this._head,
    DateTime? lostAt,
    GapReason reason = GapReason.eof,
    this.timings = const TsTimings(),
  }) : _lost = lostAt == null ? null : (at: lostAt, reason: reason);

  final ByteSource _source;
  final TsSink _sink;

  /// Timeline kept across connections.
  final TsStreamState state;

  /// Limits.
  final TsTimings timings;

  Uint8List? _head;
  ({DateTime at, GapReason reason})? _lost;

  /// Packets dropped (before the first keyframe, incomplete or damaged units, orphans).
  int droppedPackets = 0;

  /// Units dropped because packets were lost or the sync was lost.
  int damagedUnits = 0;

  /// Times the stream was cut and resumed at a keyframe inside this connection.
  int cuts = 0;

  /// Media units written by this connection.
  int units = 0;

  // Alignment.
  var _carry = Uint8List(0);
  var _synced = false;

  // Program.
  int? _pmtPid;
  List<({int pid, int type})> _streams = const [];
  Set<int> _mediaPids = const {};
  int? _videoPid;
  int? _videoType;
  int? _primaryPid;
  int? _aacPid;
  Uint8List? _asc;
  List<Uint8List> _pat = const [];
  List<Uint8List> _pmt = const [];
  final _counters = <int, int>{};
  final _lastPackets = <int, Uint8List>{};
  final _open = <int, _Unit>{};
  var _serial = 0;
  var _raiSeen = false;
  var _videoUnits = 0;

  // Writing.
  final _pending = ListQueue<_Packet>();
  var _seeking = true;
  DateTime _seekSince = clock.now();
  var _minSerial = 0;
  var _fileTicks = 0;
  final _run = BytesBuilder(copy: false);
  var _runMs = 0;
  var _runUnits = 0;

  // Lifecycle.
  var _started = false;
  var _finished = false;
  var _stopRequested = false;
  final _boundary = Completer<void>();

  /// Runs the connection until the stream ends ([ByteSource.next] returns
  /// null: completes) or fails (throws its error), or until [stop]. Throws
  /// `RecordException(unsupportedProtocol)` when no keyframe comes within
  /// [TsTimings.keyframeWait] of the start.
  Future<void> run() async {
    if (_started) throw StateError('A feed runs once');
    _started = true;
    final head = _head;
    _head = null;
    try {
      if (head != null) _process(head);
      while (!_finished) {
        await _sink.ready;
        if (_finished) break;
        final bytes = await _source.next();
        if (_finished) break;
        if (bytes == null) break;
        _process(bytes);
      }
    } finally {
      _finish();
    }
  }

  /// Stops as the user asked: waits for the video frame being received to
  /// complete (at most [wait], spec §6.7), writes what is complete and ends.
  Future<void> stop(Duration wait) async {
    if (_finished || _stopRequested) return;
    _stopRequested = true;
    if (!_seeking) await _boundary.future.timeout(wait, onTimeout: () {});
    _finish();
  }

  /// Drops the connection.
  Future<void> cancel() => _source.cancel();

  void _finish() {
    if (_finished) return;
    _finished = true;
    _cut();
    if (!_boundary.isCompleted) _boundary.complete();
  }

  // ------------------------------------------------------------ alignment

  void _process(Uint8List bytes) {
    if (_finished) return;
    final data = _carry.isEmpty
        ? bytes
        : (Uint8List(_carry.length + bytes.length)
            ..setRange(0, _carry.length, _carry)
            ..setRange(_carry.length, _carry.length + bytes.length, bytes));
    var at = 0;
    while (!_finished && !(_stopRequested && _boundary.isCompleted)) {
      if (!_synced) {
        final offset = tsSyncOffset(Uint8List.sublistView(data, at));
        if (offset == null) break;
        if (offset < 0) {
          droppedPackets++;
          at += tsPacketSize;
          continue;
        }
        at += offset;
        _synced = true;
        continue;
      }
      if (at + tsPacketSize > data.length) break;
      if (data[at] != tsSync) {
        // Lost sync: what was complete stays, the rest waits for a keyframe.
        _synced = false;
        _counters.clear();
        _lastPackets.clear();
        _cut(reason: GapReason.damaged);
        continue;
      }
      _packet(Uint8List.sublistView(data, at, at + tsPacketSize));
      at += tsPacketSize;
    }
    _carry = at >= data.length ? Uint8List(0) : Uint8List.fromList(Uint8List.sublistView(data, at));
    if (_finished) return;
    _drain();
    _flushRun();
    if (_seeking && !_stopRequested && clock.now().difference(_seekSince) > timings.keyframeWait) {
      if (units == 0) {
        throw RecordException(
          RecordErrorKind.unsupportedProtocol,
          RecordStage.stream,
          'no keyframe in ${timings.keyframeWait.inSeconds} s of MPEG-TS (scrambled or unknown content)',
        );
      }
      // Media came before: end the connection; the session reconnects.
      _finish();
    }
  }

  // --------------------------------------------------------------- packets

  _Kind? _kindOf(int pid) {
    if (pid == 0 || pid == _pmtPid) return _Kind.psi;
    if (pid == _videoPid) return _Kind.video;
    return _mediaPids.contains(pid) ? _Kind.es : null;
  }

  void _packet(Uint8List packet) {
    final error = (packet[1] & 0x80) != 0;
    final start = (packet[1] & 0x40) != 0;
    final pid = ((packet[1] & 0x1F) << 8) | packet[2];
    final control = (packet[3] >> 4) & 0x03;
    final counter = packet[3] & 0x0F;
    var payloadAt = 4;
    var discontinuity = false;
    var rai = false;
    if (control == 2 || control == 3) {
      final length = packet[4];
      if (length > 0 && length <= 183) {
        discontinuity = (packet[5] & 0x80) != 0;
        rai = (packet[5] & 0x40) != 0;
      }
      payloadAt = length > 183 ? tsPacketSize : 5 + length;
    }
    final hasPayload = (control == 1 || control == 3) && payloadAt < tsPacketSize;
    final kind = _kindOf(pid);
    if (kind == null) {
      _pending.add(_Packet(packet, null));
      _afterPacket(pid, start);
      return;
    }
    if (error) {
      _damage(pid, kind);
      _pending.add(_Packet(packet, null)..drop = true);
      return;
    }
    if (hasPayload) {
      final last = _counters[pid];
      final previous = _lastPackets[pid];
      _counters[pid] = counter;
      _lastPackets[pid] = packet;
      if (last != null && !discontinuity) {
        if (counter == last && previous != null && _samePacket(previous, packet)) {
          // A repeated packet (ISO/IEC 13818-1 2.4.3.3) stays with its unit.
          final unit = _open[pid];
          _pending.add(_Packet(packet, unit)..drop = unit == null || unit.complete);
          return;
        }
        if (counter != (last + 1) & 0x0F) _damage(pid, kind);
      }
    }
    if (!hasPayload) {
      final unit = _open[pid];
      _pending.add(_Packet(packet, unit == null || unit.complete || unit.dropped ? null : unit));
      return;
    }
    final payload = Uint8List.sublistView(packet, payloadAt);
    if (start) {
      final previous = _open.remove(pid);
      if (previous != null && !previous.complete && !previous.dropped) {
        if (previous.declared == null) {
          _complete(previous);
        } else {
          // Shorter than declared: its end was lost.
          _dropUnit(previous);
        }
      }
      final unit = kind == _Kind.psi ? _startSection(pid, payload, packet) : _startPes(pid, kind, payload, rai);
      if (unit == null) {
        _pending.add(_Packet(packet, null)..drop = true);
        return;
      }
      _open[pid] = unit;
      _pending.add(_Packet(packet, unit, first: true));
      if (unit.declared != null && unit.received >= unit.declared!) _complete(unit);
    } else {
      final unit = _open[pid];
      if (unit == null || unit.complete || unit.dropped) {
        // Belongs to a unit that began before the connection or was dropped.
        _pending.add(_Packet(packet, null)..drop = true);
        return;
      }
      unit.packets?.add(packet);
      unit.body?.add(payload);
      unit.received += payload.length;
      _pending.add(_Packet(packet, unit));
      if (unit.declared != null && unit.received >= unit.declared!) _complete(unit);
    }
    _afterPacket(pid, start);
  }

  void _afterPacket(int pid, bool start) {
    // A stop waits for the frame being received: the next one starting completes it.
    if (_stopRequested && start && pid == _primaryPid && !_boundary.isCompleted) _boundary.complete();
  }

  _Unit? _startSection(int pid, Uint8List payload, Uint8List packet) {
    if (payload.isEmpty || 1 + payload[0] >= payload.length) return null;
    final section = Uint8List.sublistView(payload, 1 + payload[0]);
    final unit = _Unit(pid, _Kind.psi, ++_serial, primary: false)
      ..body = (BytesBuilder(copy: false)..add(section))
      ..packets = [packet]
      ..received = section.length;
    if (section.length >= 3) unit.declared = 3 + (((section[1] & 0x0F) << 8) | section[2]);
    if (section[0] == 0xFF) unit.declared = 0;
    return unit;
  }

  _Unit? _startPes(int pid, _Kind kind, Uint8List payload, bool rai) {
    if (payload.length < 9 || payload[0] != 0 || payload[1] != 0 || payload[2] != 1) {
      // Not a PES start: the unit is unreadable.
      damagedUnits++;
      return null;
    }
    final length = (payload[4] << 8) | payload[5];
    final unit = _Unit(pid, kind, ++_serial, primary: pid == _primaryPid)
      ..rai = rai
      ..received = payload.length - 6;
    if (length != 0) unit.declared = length;
    final flags = payload[7] >> 6;
    if (flags >= 2 && payload.length >= 14) {
      unit.time = flags == 3 && payload.length >= 19 ? _timestamp(payload, 14) : _timestamp(payload, 9);
    }
    if (kind == _Kind.video) {
      unit.body = BytesBuilder(copy: false)..add(payload);
      if (rai) _raiSeen = true;
    } else if (pid == _aacPid) {
      final at = 9 + payload[8];
      if (at + 7 <= payload.length && payload[at] == 0xFF && (payload[at + 1] & 0xF6) == 0xF0) {
        final asc = ascOfAdts(Uint8List.sublistView(payload, at));
        final previous = _asc;
        if (previous != null && !_same(previous, asc)) {
          // Another AAC configuration: the old file ends here, the next
          // file starts at the next keyframe.
          _cut();
        }
        _asc = asc;
      }
    }
    if (unit.primary && kind == _Kind.es) unit.key = true;
    return unit;
  }

  void _complete(_Unit unit) {
    unit.complete = true;
    switch (unit.kind) {
      case _Kind.psi:
        _onSection(unit);
      case _Kind.video:
        _classify(unit);
      case _Kind.es:
        break;
    }
    unit.body = null;
  }

  void _classify(_Unit unit) {
    final pes = unit.body?.takeBytes();
    if (pes == null || pes.length < 9) return;
    final at = 9 + pes[8];
    if (at > pes.length) return;
    final es = Uint8List.sublistView(pes, at);
    _videoUnits++;
    final type = _videoType;
    final codec = type == null ? null : tsVideoCodecOf(type);
    if (codec != null) {
      if (TsDemuxer.isKeyframe(codec, es)) {
        unit.sets = parameterSetsOf(codec, es);
        unit.key = unit.sets != null;
      }
    } else if (type == 0x01 || type == 0x02) {
      unit.key = _hasSequenceHeader(es);
    } else {
      unit.key = unit.rai || (!_raiSeen && _videoUnits > timings.raiFallback);
    }
  }

  static bool _hasSequenceHeader(Uint8List es) {
    for (var i = 0; i + 3 < es.length; i++) {
      if (es[i] == 0 && es[i + 1] == 0 && es[i + 2] == 1 && es[i + 3] == 0xB3) return true;
    }
    return false;
  }

  void _onSection(_Unit unit) {
    final section = unit.body?.takeBytes();
    if (section == null || section.length < 12 || unit.declared == null || section.length < unit.declared!) return;
    final bytes = Uint8List.sublistView(section, 0, unit.declared);
    if (unit.pid == 0) {
      if (bytes[0] != 0x00) return;
      _pat = unit.packets!;
      for (var at = 8; at + 4 <= bytes.length - 4; at += 4) {
        final program = (bytes[at] << 8) | bytes[at + 1];
        if (program == 0) continue;
        _pmtPid = ((bytes[at + 2] & 0x1F) << 8) | bytes[at + 3];
        break;
      }
      return;
    }
    if (bytes[0] != 0x02 || bytes.length < 16) return;
    final streams = <({int pid, int type})>[];
    var at = 12 + (((bytes[10] & 0x0F) << 8) | bytes[11]);
    while (at + 5 <= bytes.length - 4) {
      final type = bytes[at];
      final pid = ((bytes[at + 1] & 0x1F) << 8) | bytes[at + 2];
      streams.add((pid: pid, type: type));
      at += 5 + (((bytes[at + 3] & 0x0F) << 8) | bytes[at + 4]);
    }
    final changed = _streams.isNotEmpty && !_sameStreams(_streams, streams);
    if (changed) {
      // Another program: the old file ends here, the next starts at the next keyframe.
      unit.dropped = true;
      _cut();
    }
    _pmt = unit.packets!;
    _streams = streams;
    _mediaPids = {
      for (final stream in streams)
        if (isTsVideoType(stream.type) || isTsAudioType(stream.type)) stream.pid,
    };
    final video = streams.where((stream) => isTsVideoType(stream.type)).firstOrNull;
    final audio = streams.where((stream) => isTsAudioType(stream.type)).firstOrNull;
    _videoPid = video?.pid;
    _videoType = video?.type;
    _primaryPid = video?.pid ?? audio?.pid;
    _aacPid = streams.where((stream) => stream.type == 0x0F).firstOrNull?.pid;
  }

  static bool _sameStreams(List<({int pid, int type})> a, List<({int pid, int type})> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _dropUnit(_Unit unit) {
    if (unit.dropped) return;
    unit
      ..dropped = true
      ..body = null;
    damagedUnits++;
  }

  /// Packets of [pid] were lost: its unit is damaged. After video damage
  /// the stream waits for the next keyframe (later frames refer to it).
  void _damage(int pid, _Kind kind) {
    final unit = _open.remove(pid);
    if (unit != null && !unit.complete) _dropUnit(unit);
    if (kind == _Kind.video) _cut(reason: GapReason.damaged);
  }

  // --------------------------------------------------------------- writing

  bool get _hasProgram => _pat.isNotEmpty && _pmt.isNotEmpty && _primaryPid != null;

  /// Writes out the complete units at the front; a unit still arriving
  /// holds back everything behind it (spec §8.2).
  void _drain() {
    while (_pending.isNotEmpty) {
      final packet = _pending.first;
      final unit = packet.unit;
      var resume = false;
      if (_seeking) {
        if (unit == null || !packet.first || !unit.primary || unit.dropped || !_hasProgram) {
          _pending.removeFirst();
          droppedPackets++;
          continue;
        }
        if (!unit.complete) break;
        if (!unit.key) {
          unit.dropped = true;
          _pending.removeFirst();
          droppedPackets++;
          continue;
        }
        _seeking = false;
        _minSerial = unit.serial;
        resume = true;
      } else if (unit != null && !unit.complete && !unit.dropped) {
        break;
      }
      _pending.removeFirst();
      if (packet.drop || unit != null && (unit.dropped || unit.serial < _minSerial)) {
        droppedPackets++;
        continue;
      }
      if (unit != null && packet.first && unit.primary) _unitStart(unit, resume: resume);
      _run.add(packet.bytes);
    }
  }

  void _unitStart(_Unit unit, {required bool resume}) {
    // The step from the previous unit: its duration belongs to the file
    // written so far; a hole beyond it (a reconnection) only when the file
    // goes on, where the remux keeps it too.
    final time = unit.time;
    final last = state.lastTime;
    final delta = time == null || last == null ? null : _signedDelta(time, last);
    final aligned = delta != null && delta > 0 && delta <= _window;
    final ticks = delta == null ? 0 : (aligned ? delta : state.step);
    final own = ticks < state.step ? ticks : state.step;
    _addTicks(own);
    final signature = TsSignature(
      streamTypes: [
        for (final stream in _streams)
          if (isTsVideoType(stream.type) || isTsAudioType(stream.type)) stream.type,
      ],
      parameterSets: unit.sets,
      audioConfig: _asc,
      startsWithKeyframe: true,
    );
    // The writer judges its limits by what it got (§6.5).
    if (unit.key) _flushRun();
    final newFile = unit.key && _sink.wantsFile(signature);
    if (newFile) {
      _moveEarlier(unit);
      _flushRun();
      _sink.startFile(signature);
      _fileTicks = 0;
    } else {
      _addTicks(ticks - own);
      if (unit.key) _sink.noteSignature(signature);
    }
    if (newFile || resume) {
      // The program in front of the keyframe (spec §8.2).
      [..._pat, ..._pmt].forEach(_run.add);
    }
    final lost = _lost;
    if (resume && lost != null && state.wroteMedia) {
      // Like the FLV writer: the media time in the window, else the wall time (§8.3).
      final missing = aligned ? (delta - state.step) ~/ 90 : clock.now().difference(lost.at).inMilliseconds;
      if (missing > state.step ~/ 90) {
        _flushRun();
        _sink.addMissing(HlsMissing(reason: lost.reason, missingMs: missing, wallStart: lost.at, source: 'ts'));
      }
    }
    if (resume) {
      _lost = null;
    } else if (aligned && delta <= 90000) {
      state.step = delta;
    }
    if (time != null) state.lastTime = time;
    state.wroteMedia = true;
    _runUnits++;
    units++;
  }

  void _addTicks(int ticks) {
    if (ticks <= 0) return;
    final before = _fileTicks ~/ 90;
    _fileTicks += ticks;
    _runMs += _fileTicks ~/ 90 - before;
  }

  /// Before a new file starts at [key]: the rest of the units begun before
  /// it (all complete by now) goes to the old file.
  void _moveEarlier(_Unit key) {
    for (final packet in _pending) {
      final unit = packet.unit;
      if (unit == null || packet.drop || unit.dropped || unit.serial >= key.serial || unit.serial < _minSerial) {
        continue;
      }
      _run.add(packet.bytes);
      packet.drop = true;
    }
  }

  /// Ends what is being written: complete units are written, the rest is
  /// dropped; afterwards the stream waits for a keyframe. [reason] records
  /// a gap there (damage).
  void _cut({GapReason? reason}) {
    for (final unit in _open.values) {
      if (!unit.complete) {
        unit
          ..dropped = true
          ..body = null;
      }
    }
    _open.clear();
    final wasSeeking = _seeking;
    _drain();
    for (final packet in _pending) {
      if (!packet.drop) droppedPackets++;
    }
    _pending.clear();
    _flushRun();
    _seeking = true;
    _seekSince = clock.now();
    if (!wasSeeking && !_finished) cuts++;
    if (reason != null && state.wroteMedia && _lost == null) _lost = (at: clock.now(), reason: reason);
  }

  void _flushRun() {
    if (_run.isEmpty && _runMs == 0 && _runUnits == 0) return;
    _sink.addPackets(_run.takeBytes(), durationMs: _runMs, units: _runUnits);
    _runMs = 0;
    _runUnits = 0;
  }

  // --------------------------------------------------------------- helpers

  static const int _wrap = 1 << 33;
  static const int _window = 60 * 90000;

  static int _signedDelta(int time, int last) {
    var delta = (time - last) % _wrap;
    if (delta > _wrap >> 1) delta -= _wrap;
    return delta;
  }

  static int _timestamp(Uint8List data, int at) =>
      ((data[at] >> 1) & 0x07) * (1 << 30) +
      (data[at + 1] << 22) +
      ((data[at + 2] >> 1) << 15) +
      (data[at + 3] << 7) +
      (data[at + 4] >> 1);

  static bool _samePacket(Uint8List a, Uint8List b) {
    for (var i = 4; i < tsPacketSize; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
