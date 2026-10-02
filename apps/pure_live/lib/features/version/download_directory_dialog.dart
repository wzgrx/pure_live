import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The answer to [showDownloadDirectoryDialog].
enum DownloadDirectoryChoice {
  /// Keep the platform's default folder.
  useDefault,

  /// Open the system folder picker.
  pick,
}

/// Asks where updates, downloads and fonts go when there is no usable
/// download folder yet (3.x `showDownloadDirectoryChoiceDialog`,
/// docs/A-界面设计/A06-首页和全局/A06.3-全局弹窗): the message, the default folder, and "取消",
/// "使用默认目录", "选择目录". Null is cancel, also from a tap outside, Back and
/// Esc (U.3d c6; 3.x had no way out but the two choices). Without a picker
/// ([canPick] false) "选择目录" is not offered.
Future<DownloadDirectoryChoice?> showDownloadDirectoryDialog(
  BuildContext context, {
  required String defaultPath,
  bool canPick = true,
}) => showAppDialog<DownloadDirectoryChoice>(
  context: context,
  builder: (_) => DownloadDirectoryDialog(defaultPath: defaultPath, canPick: canPick),
);

/// The dialog of [showDownloadDirectoryDialog].
class DownloadDirectoryDialog extends StatelessWidget {
  /// Creates the dialog.
  const new({required this.defaultPath, this.canPick = true, super.key});

  /// The default folder.
  final String defaultPath;

  /// Whether "选择目录" is offered.
  final bool canPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    return AppDialog(
      key: const ValueKey('download-directory-dialog'),
      title: i18n('download_directory_prompt_title'),
      message: i18n('download_directory_prompt_message'),
      onEnter: () =>
          Navigator.of(context).pop(canPick ? DownloadDirectoryChoice.pick : DownloadDirectoryChoice.useDefault),
      content: defaultPath.trim().isEmpty
          ? null
          : SelectableText(
              i18n('download_directory_default_path', args: {'path': defaultPath.trim()}),
              key: const ValueKey('download-directory-default-path'),
              style: styles.t14.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
            ),
      actions: [
        DialogCancelButton(
          key: const ValueKey('download-directory-cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (canPick)
          TextButton(
            key: const ValueKey('download-directory-use-default'),
            onPressed: () => Navigator.of(context).pop(DownloadDirectoryChoice.useDefault),
            child: Text(i18n('download_directory_use_default')),
          )
        else
          DialogActionButton(
            key: const ValueKey('download-directory-use-default'),
            label: i18n('download_directory_use_default'),
            onPressed: () => Navigator.of(context).pop(DownloadDirectoryChoice.useDefault),
          ),
        if (canPick)
          DialogActionButton(
            key: const ValueKey('download-directory-pick'),
            label: i18n('download_directory_choose'),
            onPressed: () => Navigator.of(context).pop(DownloadDirectoryChoice.pick),
          ),
      ],
    );
  }
}
