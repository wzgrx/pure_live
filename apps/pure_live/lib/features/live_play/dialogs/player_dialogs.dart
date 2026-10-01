import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/i18n/i18n.dart';

// The pickers the video's buttons open. They keep the plain list look of the
// room's other dialogs until the dialogs get their own design (U.2f).

/// 3.x's video fit list: the setting `videoFitIndex` is an index into it.
const List<BoxFit> videoFits = [
  BoxFit.contain,
  BoxFit.cover,
  BoxFit.fill,
  BoxFit.fitHeight,
  BoxFit.fitWidth,
  BoxFit.scaleDown,
];

/// The names of [videoFits] (3.x `AppConsts.videoFitType`).
const List<String> videoFitKeys = [
  'video_fit_default',
  'video_fit_crop_center',
  'video_fit_fill_screen',
  'video_fit_fit_height',
  'video_fit_fit_width',
  'video_fit_scale_down',
];

/// The fit stored in [settings], as an index of [videoFits].
int videoFitIndexOf(SettingsStore settings) => settings.get(Settings.videoFitIndex).clamp(0, videoFits.length - 1);

/// The name of fit [index].
String videoFitName(int index) => i18n(videoFitKeys[index.clamp(0, videoFitKeys.length - 1)]);

/// The next fit (3.x `advanceVideoFitIndex`: the fullscreen text button).
Future<void> advanceVideoFit(SettingsStore settings) =>
    settings.set(Settings.videoFitIndex, (videoFitIndexOf(settings) + 1) % videoFits.length);

/// Picks the picture's fit (the room menu's "画面比例").
Future<void> showVideoFitPicker(BuildContext context, SettingsStore settings) async {
  final current = videoFitIndexOf(settings);
  final chosen = await showDialog<int>(
    context: context,
    builder: (dialogContext) => _ChoiceDialog(
      title: i18n('settings_video_fit'),
      keyPrefix: 'video-fit',
      options: [for (var index = 0; index < videoFits.length; index++) videoFitName(index)],
      selected: current,
    ),
  );
  if (chosen != null && chosen != current) await settings.set(Settings.videoFitIndex, chosen);
}

/// The name of [orientation] (3.x's keys).
String roomOrientationName(RoomOrientation orientation) => i18n(switch (orientation) {
  RoomOrientation.automatic => 'portrait_override_auto',
  RoomOrientation.portrait => 'portrait_override_portrait',
  RoomOrientation.landscape => 'portrait_override_landscape',
});

/// Picks the room's orientation and whether to remember it (3.x
/// `PortraitOrientationPickerDialog`).
Future<void> showRoomOrientationPicker(BuildContext context, RoomOrientationChoice choice) async {
  final result = await showDialog<(RoomOrientation, bool)>(
    context: context,
    builder: (dialogContext) => _OrientationDialog(selected: choice.value, remember: choice.remember),
  );
  if (result case (final orientation, final remember)) {
    await choice.choose(orientation, remember: remember);
  }
}

class _ChoiceDialog extends StatelessWidget {
  const new({required this.title, required this.keyPrefix, required this.options, required this.selected});

  final String title;
  final String keyPrefix;
  final List<String> options;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, option) in options.indexed)
                ListTile(
                  key: ValueKey('$keyPrefix-$index'),
                  title: Text(option),
                  trailing: index == selected ? Icon(AppIcons.selected, color: scheme.primary) : null,
                  onTap: () => Navigator.of(context).pop(index),
                ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel')))],
    );
  }
}

class _OrientationDialog extends StatefulWidget {
  const new({required this.selected, required this.remember});

  final RoomOrientation selected;
  final bool remember;

  @override
  State<_OrientationDialog> createState() => _OrientationDialogState();
}

class _OrientationDialogState extends State<_OrientationDialog> {
  late bool _remember = widget.remember;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(i18n('portrait_room_override')),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final orientation in RoomOrientation.values)
                ListTile(
                  key: ValueKey('room-orientation-${orientation.name}'),
                  title: Text(roomOrientationName(orientation)),
                  trailing: orientation == widget.selected ? Icon(AppIcons.selected, color: scheme.primary) : null,
                  onTap: () => Navigator.of(context).pop((orientation, _remember)),
                ),
              SwitchListTile(
                key: const ValueKey('room-orientation-remember'),
                title: Text(i18n('portrait_remember_room_override')),
                subtitle: Text(i18n('portrait_remember_room_override_desc')),
                value: _remember,
                onChanged: (value) => setState(() => _remember = value),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel')))],
    );
  }
}
