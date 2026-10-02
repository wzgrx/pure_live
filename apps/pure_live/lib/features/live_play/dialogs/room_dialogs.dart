import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';

// The room menu's "定时关闭" and "房间音量" (docs/ui/compare/U.2n c1): room
// panels like the record and danmaku settings ones, under the picture in
// portrait, on the right in landscape and on tablets; 3.x and 4.0.0 showed
// centred dialogs over the picture.

/// Opens "定时关闭" (3.x `RoomTimerDialog`): the room's panel, or the same
/// panel in a sheet where there is no room page around [context].
void showSleepTimer(BuildContext context, LiveRoomController controller) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels != null) {
    panels.open(RoomPanelKind.sleepTimer);
    return;
  }
  unawaited(
    showRoomPanelSheet(
      context,
      builder: (_, close) => RoomSleepTimerPanel(controller: controller, onClose: close),
    ),
  );
}

/// The lengths offered (3.x `RoomTimerDialog`).
const List<int> sleepTimerPresets = [15, 30, 45, 60, 90, 120, 240, 480];

/// The longest sleep timer in minutes (365 days, 3.x).
const int sleepTimerMaxMinutes = 525600;

/// "定时关闭" (docs/ui/compare/U.2n c1, c11): the switch, the preset lengths
/// and a length of one's own. Changes apply at once (N2): the switch starts
/// or stops the timer, a preset starts it, "开始" starts the typed length;
/// the panel stays and says when the room pauses. When the timer ends the
/// room pauses (3.x).
class RoomSleepTimerPanel extends StatefulWidget {
  /// Creates the panel.
  const new({required this.controller, required this.onClose, this.dragToClose = false, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Closes the panel.
  final VoidCallback onClose;

  /// A downward drag on the header closes it (portrait).
  final bool dragToClose;

  @override
  State<RoomSleepTimerPanel> createState() => _RoomSleepTimerPanelState();
}

class _RoomSleepTimerPanelState extends State<RoomSleepTimerPanel> {
  late final TextEditingController _minutes = TextEditingController(text: '${widget.controller.sleepMinutes}');
  String? _error;

  /// "X 分钟后暂停" moves on while the panel is open.
  Timer? _tick;

  LiveRoomController get _room => widget.controller;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _room.sleepDeadline != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _minutes.dispose();
    super.dispose();
  }

  int? get _typed {
    final minutes = int.tryParse(_minutes.text.trim());
    return minutes == null || minutes < 1 || minutes > sleepTimerMaxMinutes ? null : minutes;
  }

  void _start(int minutes) {
    _room.setSleepTimer(enabled: true, minutes: minutes);
    setState(() {
      _minutes.text = '$minutes';
      _error = null;
    });
  }

  void _switch(bool on) {
    // Turning the timer off stays possible with an unfinished length.
    _room.setSleepTimer(enabled: on, minutes: _typed ?? _room.sleepMinutes);
    setState(() {
      if (on) _minutes.text = '${_room.sleepMinutes}';
      _error = null;
    });
  }

  void _submit() {
    final minutes = _typed;
    if (minutes == null) {
      setState(() => _error = i18n('room_playback_timer_custom_hint'));
      return;
    }
    FocusScope.of(context).unfocus();
    _start(minutes);
  }

  String _left(DateTime deadline) {
    final left = deadline.difference(_room.now());
    final time = TimeOfDay.fromDateTime(deadline);
    String two(int value) => value.toString().padLeft(2, '0');
    return i18n(
      'live_play_timer_left_until',
      args: {'minutes': '${left.inMinutes + 1}', 'time': '${two(time.hour)}:${two(time.minute)}'},
    );
  }

  @override
  Widget build(BuildContext context) => RoomSidePanel(
    key: const ValueKey('room-timer-panel'),
    title: i18n('sleep_timer'),
    onClose: widget.onClose,
    dragToClose: widget.dragToClose,
    child: ListenableBuilder(
      listenable: _room,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final deadline = _room.sleepDeadline;
        final on = deadline != null;
        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const SizedBox(height: 4),
            PanelCard(
              children: [
                MergeSemantics(
                  child: InkWell(
                    onTap: () => _switch(!on),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  i18n('room_playback_timer_enable'),
                                  style: theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  on ? _left(deadline) : i18n('room_playback_timer_desc'),
                                  key: const ValueKey('room-timer-status'),
                                  style: on
                                      ? theme.textTheme.bodyMedium?.emphasis.copyWith(color: scheme.primary)
                                      : theme.textTheme.bodyMedium?.regular.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Switch(key: const ValueKey('room-timer-enabled'), value: on, onChanged: _switch),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            PanelGroupTitle(i18n('room_playback_timer_duration')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in sleepTimerPresets)
                    ChoiceChip(
                      key: ValueKey('room-timer-preset-$minutes'),
                      label: Text('$minutes ${i18n('minutes')}'),
                      selected: on && _room.sleepMinutes == minutes,
                      onSelected: (_) => _start(minutes),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('room-timer-duration'),
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onSubmitted: (_) => _submit(),
                      decoration: dialogFieldDecoration(
                        context,
                        label: i18n('settings_custom_value'),
                        suffix: i18n('minutes'),
                        helper: i18n('room_playback_timer_custom_hint'),
                        error: _error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      key: const ValueKey('room-timer-confirm'),
                      onPressed: _submit,
                      child: Text(i18n('start')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Opens "房间音量": the room's panel, or the same panel in a sheet where
/// there is no room page around [context].
void showRoomVolume(BuildContext context, LiveRoomController controller) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels != null) {
    panels.open(RoomPanelKind.volume);
    return;
  }
  unawaited(
    showRoomPanelSheet(
      context,
      heightFactor: 0.4,
      builder: (_, close) => RoomVolumePanel(controller: controller, onClose: close),
    ),
  );
}

/// The volume to come back to when the sound is turned on again (B-14):
/// the phone's media volume before it was muted here, and each room's.
double? _systemBeforeMute;
final Expando<double> _roomBeforeMute = Expando('room volume before mute');

/// The volume "取消静音" goes to when nothing was heard before (N5).
const double unmuteFallbackVolume = 0.5;

/// "房间音量" (docs/ui/compare/U.2n c1–c3): the mute button, the slider and
/// the level. Where the picture's drags change the phone's media volume
/// ([DeviceControls], Android phones and tablets; B-3, 3.x's
/// `_usesSystemVolume`), this is that same volume: nothing of its own is
/// kept, and it follows the volume keys and the drags while open. Elsewhere
/// it is the player's volume, kept for this room (3.x
/// `LiveRoomVolumeManager`). The sound comes back at the volume it had
/// before muting (B-14).
class RoomVolumePanel extends StatefulWidget {
  /// Creates the panel.
  const new({required this.controller, required this.onClose, this.dragToClose = false, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Closes the panel.
  final VoidCallback onClose;

  /// A downward drag on the header closes it (portrait).
  final bool dragToClose;

  @override
  State<RoomVolumePanel> createState() => _RoomVolumePanelState();
}

class _RoomVolumePanelState extends State<RoomVolumePanel> {
  /// The phone's media volume (the drags' and the keys' volume).
  final bool _system = DeviceControls.available;
  double? _level;
  bool _dragging = false;
  Timer? _follow;

  LiveRoomController get _room => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_system) {
      unawaited(_read());
      // The volume keys and the drags change it while the panel is open.
      _follow = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_read()));
    }
  }

  @override
  void dispose() {
    _follow?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    if (_dragging) return;
    final level = await DeviceControls.volume();
    if (!mounted || level == null || _dragging || level == _level) return;
    setState(() => _level = level);
  }

  double get _value => (_system ? (_level ?? 0) : _room.volume).clamp(0.0, 1.0);

  Future<void> _set(double value, {bool keep = false}) async {
    final level = value.clamp(0.0, 1.0);
    if (_system) {
      setState(() => _level = level);
      await DeviceControls.setVolume(level);
    } else {
      await _room.setVolume(level, save: keep);
    }
  }

  void _toggleMute() {
    final now = _value;
    if (now > 0) {
      if (_system) {
        _systemBeforeMute = now;
      } else {
        _roomBeforeMute[_room] = now;
      }
      unawaited(_set(0, keep: true));
    } else {
      final before = _system ? _systemBeforeMute : _roomBeforeMute[_room];
      unawaited(_set(before ?? unmuteFallbackVolume, keep: true));
    }
  }

  @override
  Widget build(BuildContext context) => RoomSidePanel(
    key: const ValueKey('room-volume-panel'),
    title: i18n('room_volume'),
    onClose: widget.onClose,
    dragToClose: widget.dragToClose,
    child: ListenableBuilder(
      // The player's volume changes with the bar's slider and the keys.
      listenable: _room,
      builder: (context, _) {
        final theme = Theme.of(context);
        final value = _value;
        final percent = '${(value * 100).round()}%';
        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('room-volume-mute'),
                    tooltip: i18n(value <= 0 ? 'live_play_unmute' : 'live_play_mute'),
                    onPressed: _toggleMute,
                    icon: Icon(volumeIcon(value)),
                  ),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('room-volume-slider'),
                      value: value,
                      divisions: 20,
                      label: percent,
                      semanticFormatterCallback: (_) => percent,
                      onChangeStart: (_) => _dragging = true,
                      onChanged: (level) => unawaited(_set(level)),
                      onChangeEnd: (level) {
                        _dragging = false;
                        // The player's volume is kept for the room once the
                        // slider rests (the system keeps its own).
                        if (!_system) unawaited(_room.saveVolume());
                      },
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      percent,
                      key: const ValueKey('room-volume-value'),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyLarge?.emphasis.tabular,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                i18n(_system ? 'live_play_volume_system_hint' : 'live_play_volume_room_hint'),
                style: theme.textTheme.bodyMedium?.regular.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// The icon of a volume (3.x).
IconData volumeIcon(double volume) => volume <= 0
    ? AppIcons.volumeMuted
    : volume < 0.5
    ? AppIcons.volumeLow
    : AppIcons.volumeHigh;
