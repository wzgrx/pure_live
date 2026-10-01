import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/live_play/room_controller.dart';

/// The sleep timer of the room (3.x `RoomTimerDialog`): a switch, preset
/// lengths and a minute field; when it ends the room pauses.
Future<void> showSleepTimerDialog(BuildContext context, LiveRoomController controller) => showDialog<void>(
  context: context,
  builder: (_) => _SleepTimerDialog(controller: controller),
);

class _SleepTimerDialog extends StatefulWidget {
  const new({required this.controller});

  final LiveRoomController controller;

  @override
  State<_SleepTimerDialog> createState() => _SleepTimerDialogState();
}

class _SleepTimerDialogState extends State<_SleepTimerDialog> {
  static const List<int> _presets = [15, 30, 45, 60, 90, 120, 240, 480];
  static const int _max = 525600;

  late final TextEditingController _minutes;
  late bool _enabled;
  String? _error;

  @override
  void initState() {
    super.initState();
    _enabled = widget.controller.sleepDeadline != null;
    _minutes = TextEditingController(text: '${widget.controller.sleepMinutes}');
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _submit() {
    final minutes = int.tryParse(_minutes.text.trim());
    if (_enabled && (minutes == null || minutes < 1 || minutes > _max)) {
      setState(() => _error = i18n('room_playback_timer_custom_hint'));
      return;
    }
    // Turning the timer off stays possible with an unfinished draft.
    widget.controller.setSleepTimer(enabled: _enabled, minutes: minutes ?? widget.controller.sleepMinutes);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = widget.controller.sleepDeadline;
    final left = deadline?.difference(widget.controller.now());
    return AlertDialog(
      title: Text(i18n('room_playback_timer')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                key: const ValueKey('room-timer-enabled'),
                contentPadding: EdgeInsets.zero,
                title: Text(i18n('room_playback_timer_enable')),
                subtitle: Text(
                  left != null && !left.isNegative
                      ? i18n('live_play_timer_left', args: {'minutes': '${left.inMinutes + 1}'})
                      : i18n('room_playback_timer_desc'),
                ),
                value: _enabled,
                onChanged: (value) => setState(() {
                  _enabled = value;
                  _error = null;
                }),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in _presets)
                    ChoiceChip(
                      key: ValueKey('room-timer-preset-$minutes'),
                      label: Text('$minutes ${i18n('minutes')}'),
                      selected: _minutes.text == '$minutes',
                      onSelected: _enabled
                          ? (_) => setState(() {
                              _minutes.text = '$minutes';
                              _error = null;
                            })
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('room-timer-duration'),
                controller: _minutes,
                enabled: _enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: i18n('room_playback_timer_duration'),
                  suffixText: i18n('minutes'),
                  helperText: i18n('room_playback_timer_custom_hint'),
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
        FilledButton(key: const ValueKey('room-timer-confirm'), onPressed: _submit, child: Text(i18n('confirm'))),
      ],
    );
  }
}

/// The room's player volume (3.x `RoomVolumeDialog`): a slider that plays
/// at once and is kept for this room when the dialog closes.
Future<void> showRoomVolumeDialog(BuildContext context, LiveRoomController controller) async {
  final before = controller.volume;
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _VolumeDialog(controller: controller),
  );
  if (saved ?? false) {
    await controller.saveVolume();
  } else {
    await controller.setVolume(before);
  }
}

class _VolumeDialog extends StatefulWidget {
  const new({required this.controller});

  final LiveRoomController controller;

  @override
  State<_VolumeDialog> createState() => _VolumeDialogState();
}

class _VolumeDialogState extends State<_VolumeDialog> {
  late double _value = widget.controller.volume;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(i18n('room_volume')),
    content: SizedBox(
      width: 380,
      child: Row(
        children: [
          IconButton(
            tooltip: i18n(_value <= 0 ? 'live_play_unmute' : 'live_play_mute'),
            onPressed: () {
              setState(() => _value = _value <= 0 ? 1 : 0);
              unawaited(widget.controller.setVolume(_value));
            },
            icon: Icon(volumeIcon(_value)),
          ),
          Expanded(
            child: Slider(
              key: const ValueKey('room-volume-slider'),
              value: _value,
              divisions: 20,
              label: '${(_value * 100).round()}%',
              onChanged: (value) {
                setState(() => _value = value);
                unawaited(widget.controller.setVolume(value));
              },
            ),
          ),
          SizedBox(width: 44, child: Text('${(_value * 100).round()}%', textAlign: TextAlign.end)),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(i18n('cancel'))),
      FilledButton(
        key: const ValueKey('room-volume-save'),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(i18n('confirm')),
      ),
    ],
  );
}

/// The icon of a volume (3.x).
IconData volumeIcon(double volume) => volume <= 0
    ? Icons.volume_off_rounded
    : volume < 0.5
    ? Icons.volume_down_rounded
    : Icons.volume_up_rounded;
