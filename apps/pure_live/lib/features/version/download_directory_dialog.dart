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
/// docs/ui/compare/U.3d): the message, the default folder, and "取消",
/// "使用默认目录", "选择目录". Null is cancel, also from a tap outside, Back and
/// Esc (U.3d c6; 3.x had no way out but the two choices). Without a picker
/// ([canPick] false) "选择目录" is not offered.
Future<DownloadDirectoryChoice?> showDownloadDirectoryDialog(
  BuildContext context, {
  required String defaultPath,
  bool canPick = true,
}) => showDialog<DownloadDirectoryChoice>(
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
    return DialogButtonsTheme(
      child: DialogKeys(
        onEnter: () =>
            Navigator.of(context).pop(canPick ? DownloadDirectoryChoice.pick : DownloadDirectoryChoice.useDefault),
        child: AlertDialog(
          key: const ValueKey('download-directory-dialog'),
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: Text(i18n('download_directory_prompt_title')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n('download_directory_prompt_message'),
                  style: styles.t14.copyWith(color: scheme.onSurface, height: 1.5),
                ),
                if (defaultPath.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    i18n('download_directory_default_path', args: {'path': defaultPath.trim()}),
                    key: const ValueKey('download-directory-default-path'),
                    style: styles.t14.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            Row(
              children: [
                TextButton(
                  key: const ValueKey('download-directory-cancel'),
                  style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(i18n('cancel')),
                ),
                // The two choices at the right, wrapping with a large font.
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        key: const ValueKey('download-directory-use-default'),
                        onPressed: () => Navigator.of(context).pop(DownloadDirectoryChoice.useDefault),
                        child: Text(i18n('download_directory_use_default')),
                      ),
                      if (canPick)
                        FilledButton(
                          key: const ValueKey('download-directory-pick'),
                          onPressed: () => Navigator.of(context).pop(DownloadDirectoryChoice.pick),
                          child: Text(i18n('download_directory_choose')),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
