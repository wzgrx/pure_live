import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/features/settings/settings_search.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The recording folder (spec/modules/record.md §15): the chosen folder is a
/// parent; recordings go into its `PureLiveRecords` folder. Empty = default.
class RecordDirectoryTile extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => SettingAnchor(id: Settings.recordDirectory.id, child: _tile());

  Widget _tile() => SettingBuilder<String>(
    setting: Settings.recordDirectory,
    builder: (context, value, set) => ListTile(
      title: Text(t.settings.record.directory),
      subtitle: Text(value.isEmpty ? t.settings.record.directoryDefault : '$value/PureLiveRecords'),
      trailing: value.isEmpty
          ? const Icon(Icons.folder_open)
          : IconButton(
              tooltip: t.settings.record.directoryReset,
              icon: const Icon(Icons.restore),
              onPressed: () => set(''),
            ),
      onTap: () async {
        final chosen = await FilePicker.getDirectoryPath(dialogTitle: t.settings.record.directoryPick);
        if (chosen != null) set(chosen);
      },
    ),
  );
}
