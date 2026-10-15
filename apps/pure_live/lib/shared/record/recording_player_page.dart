import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The endings of the files the recorder writes (and that mpv plays).
const Set<String> recordingExtensions = {'.mp4', '.flv', '.ts', '.mkv', '.m4a', '.aac', '.mp3'};

/// The recordings of [path]'s room, oldest first (V01.8 选集). The recorder
/// writes `<platform>/<streamer>/<date>/<time>/<file>`, so the room is the
/// folder above the date and time folders; everything under it is listed
/// (at most [limit] files), and a folder of another layout lists itself.
List<String> recordingsBeside(String path, {int limit = 500}) {
  var room = Directory(p.dirname(path));
  final dated = RegExp(r'^\d{4}-\d{2}-\d{2}$|^\d{2}-\d{2}-\d{2}$');
  for (var i = 0; i < 2 && dated.hasMatch(p.basename(room.path)); i++) {
    room = room.parent;
  }
  final files = <String>[];
  try {
    for (final entity in room.listSync(recursive: true)) {
      if (entity is File && recordingExtensions.contains(p.extension(entity.path).toLowerCase())) {
        files.add(entity.path);
        if (files.length >= limit) break;
      }
    }
  } on FileSystemException {
    // Unreadable: only the file itself.
  }
  if (!files.contains(path)) files.add(path);
  // The date and time folders sort as they were recorded.
  files.sort((a, b) => p.relative(a, from: room.path).compareTo(p.relative(b, from: room.path)));
  return files;
}

/// What the engine opens for the recording at [path]: a `file://` URL
/// (mpv decodes it), so folder names in any script survive.
String recordingUrl(String path) => Uri.file(path).toString();

/// The meta key of where [path] was left (V01.8).
String recordingPositionKey(String path) => 'recording.position.${path.hashCode.toUnsigned(32)}';

/// Where a recording [duration] long that was left at [saved] starts again:
/// from the start when it was barely begun or nearly done.
Duration resumePosition(Duration saved, Duration duration) {
  if (saved < const Duration(seconds: 5)) return Duration.zero;
  if (duration > Duration.zero && saved > duration - const Duration(seconds: 5)) return Duration.zero;
  return saved;
}

/// The speeds offered (V01.8 倍速).
const List<double> recordingSpeeds = [0.5, 0.75, 1, 1.25, 1.5, 2, 3];

/// Plays a recording in the app (V01.8; 3.x and 4.x handed it to another
/// app): the picture, play and pause, a seek bar, the speed, the other
/// recordings of the room before and after it; each file starts where it
/// was left.
class RecordingPlayerPage extends ConsumerStatefulWidget {
  /// Creates the page for [files], showing [index].
  const new({required this.files, required this.index, super.key});

  /// The recordings, in order.
  final List<String> files;

  /// The one to play first.
  final int index;

  @override
  ConsumerState<RecordingPlayerPage> createState() => _RecordingPlayerPageState();
}

class _RecordingPlayerPageState extends ConsumerState<RecordingPlayerPage> {
  late final PlaybackSession _session = ref.read(playbackSessionFactoryProvider)();
  late int _index = widget.index;
  double _speed = 1;
  Duration? _dragging;
  Timer? _saveTimer;
  StreamSubscription<PlaybackState>? _states;
  PlaybackState _state = const PlaybackState();

  MetaStore get _meta => ref.read(storeProvider).meta;

  String get _path => widget.files[_index];

  @override
  void initState() {
    super.initState();
    _states = _session.states.listen((state) {
      if (mounted) setState(() => _state = state);
    });
    unawaited(_open());
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_save()));
  }

  Future<void> _open() async {
    final saved = int.tryParse(await _meta.get(recordingPositionKey(_path)) ?? '') ?? 0;
    if (!mounted) return;
    final start = saved > 5000 ? Duration(milliseconds: saved) : null;
    await _session.open(
      PlaybackRequest(
        site: 'recording',
        // A file URL: a bare path with Chinese folder names would reach mpv
        // percent-encoded and not be found.
        plan: PlaybackPlan.of(
          LivePlayUrlResolution.lines([LivePlayLine(recordingUrl(_path))]),
          onDemand: true,
          start: start,
        ),
      ),
    );
    if (_speed != 1) await _session.setRate(_speed);
  }

  Future<void> _save() async {
    final state = _session.state;
    if (state.duration <= Duration.zero) return;
    final at = resumePosition(state.position, state.duration);
    await _meta.set(recordingPositionKey(_path), '${at.inMilliseconds}');
  }

  Future<void> _go(int index) async {
    if (index < 0 || index >= widget.files.length || index == _index) return;
    await _save();
    setState(() => _index = index);
    await _open();
  }

  Future<void> _pickSpeed() async {
    final picked = await showAppOptionDialog<double>(
      context: context,
      title: i18n('recording_speed'),
      options: [for (final speed in recordingSpeeds) AppDialogOption(value: speed, label: '${_speedText(speed)}×')],
      selected: _speed,
    );
    if (picked == null || !mounted) return;
    setState(() => _speed = picked);
    await _session.setRate(picked);
  }

  static String _speedText(double speed) => speed == speed.roundToDouble() ? '${speed.round()}' : '$speed';

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_save().whenComplete(_session.dispose));
    unawaited(_states?.cancel());
    super.dispose();
  }

  static String _time(Duration value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final duration = _state.duration;
    final position = _dragging ?? _state.position;
    final playing = _state.status == PlaybackStatus.playing || _state.status == PlaybackStatus.buffering;
    final max = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    return Scaffold(
      key: const ValueKey('recording-player'),
      backgroundColor: OnVideoColors.ground,
      appBar: AppBar(
        backgroundColor: OnVideoColors.ground,
        foregroundColor: OnVideoColors.foreground,
        title: Text(p.basename(_path), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(child: LiveVideoView(session: _session)),
          if (_state.status == PlaybackStatus.error)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(i18n('record_panel_play_failed'), style: const TextStyle(color: OnVideoColors.foreground)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Text(_time(position), style: const TextStyle(color: OnVideoColors.foreground).tabular),
                Expanded(
                  child: Slider(
                    key: const ValueKey('recording-seek'),
                    value: position.inMilliseconds.clamp(0, max).toDouble(),
                    max: max,
                    onChanged: duration > Duration.zero
                        ? (value) => setState(() => _dragging = Duration(milliseconds: value.round()))
                        : null,
                    onChangeEnd: (value) {
                      setState(() => _dragging = null);
                      unawaited(_session.seek(Duration(milliseconds: value.round())));
                    },
                  ),
                ),
                Text(_time(duration), style: const TextStyle(color: OnVideoColors.foreground).tabular),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const ValueKey('recording-previous'),
                    tooltip: i18n('recording_previous'),
                    color: OnVideoColors.foreground,
                    onPressed: _index > 0 ? () => unawaited(_go(_index - 1)) : null,
                    icon: const Icon(AppIcons.recordingPrevious),
                  ),
                  IconButton(
                    key: const ValueKey('recording-play'),
                    tooltip: i18n(playing ? 'media_pause' : 'media_play'),
                    color: OnVideoColors.foreground,
                    iconSize: 40,
                    onPressed: () => unawaited(_session.togglePlayPause()),
                    icon: Icon(playing ? AppIcons.pause : AppIcons.play),
                  ),
                  IconButton(
                    key: const ValueKey('recording-next'),
                    tooltip: i18n('recording_next'),
                    color: OnVideoColors.foreground,
                    onPressed: _index < widget.files.length - 1 ? () => unawaited(_go(_index + 1)) : null,
                    icon: const Icon(AppIcons.recordingNext),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    key: const ValueKey('recording-speed'),
                    onPressed: () => unawaited(_pickSpeed()),
                    child: Text('${_speedText(_speed)}×', style: const TextStyle(color: OnVideoColors.foreground)),
                  ),
                  if (widget.files.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '${_index + 1} / ${widget.files.length}',
                        key: const ValueKey('recording-count'),
                        style: const TextStyle(color: OnVideoColors.secondary).tabular,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
