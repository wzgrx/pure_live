import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';

/// The recording folder (spec/modules/record.md §15): the chosen folder is a
/// parent; recordings go into its `PureLiveRecords` folder. Empty = default.
class RecordDirectoryTile extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => SettingBuilder<String>(
    setting: Settings.recordDirectory,
    builder: (context, value, set) => ListTile(
      title: const Text('录制保存位置'),
      subtitle: Text(value.isEmpty ? '默认位置' : '$value/PureLiveRecords'),
      trailing: value.isEmpty
          ? const Icon(Icons.folder_open)
          : IconButton(tooltip: '恢复默认', icon: const Icon(Icons.restore), onPressed: () => set('')),
      onTap: () async {
        final chosen = await FilePicker.getDirectoryPath(dialogTitle: '选择录制保存位置');
        if (chosen != null) set(chosen);
      },
    ),
  );
}
