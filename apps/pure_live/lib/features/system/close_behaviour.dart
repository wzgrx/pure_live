import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';

/// What closing the window does now (F-WIN-04).
enum CloseChoice {
  /// Quit.
  exit,

  /// Hide to the tray.
  minimize,

  /// Ask the user.
  ask,
}

/// Decides what closing the window does: an extra window (F-WIN-02) always
/// quits; otherwise the remembered choice applies after "不再询问", and the
/// user is asked before that.
CloseChoice closeChoice({required bool secondaryWindow, required bool dontAsk, required CloseAction action}) {
  if (secondaryWindow) return CloseChoice.exit;
  if (!dontAsk) return CloseChoice.ask;
  return action == CloseAction.minimize ? CloseChoice.minimize : CloseChoice.exit;
}

/// The user's answer in the close dialog.
typedef CloseAnswer = ({CloseAction action, bool remember});

/// Asks whether to quit or hide to the tray, with "不再询问"; null when the
/// dialog was dismissed.
Future<CloseAnswer?> showCloseDialog(BuildContext context) =>
    showDialog<CloseAnswer>(context: context, builder: (context) => const _CloseDialog());

class _CloseDialog extends StatefulWidget {
  const new();

  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  var _remember = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('关闭窗口'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('退出纯粹直播，还是最小化到托盘继续运行？'),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _remember,
          title: const Text('不再询问'),
          subtitle: const Text('可以在 设置 › 通用 里修改'),
          onChanged: (value) => setState(() => _remember = value ?? false),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, (action: CloseAction.minimize, remember: _remember)),
        child: const Text('最小化到托盘'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (action: CloseAction.exit, remember: _remember)),
        child: const Text('退出'),
      ),
    ],
  );
}

/// "关闭窗口时" in 设置 › 通用 (Windows): ask every time, hide to the tray or
/// quit.
class CloseBehaviourTile extends StatelessWidget {
  /// Creates the tile.
  const new({super.key});

  static const Map<CloseAction?, String> _labels = {
    null: '每次询问',
    CloseAction.minimize: '最小化到托盘',
    CloseAction.exit: '退出应用',
  };

  @override
  Widget build(BuildContext context) => SettingBuilder<bool>(
    setting: Settings.closeDontAsk,
    builder: (context, dontAsk, setDontAsk) => SettingBuilder<CloseAction>(
      setting: Settings.closeAction,
      builder: (context, action, setAction) {
        final current = dontAsk ? action : null;
        return ListTile(
          title: const Text('关闭窗口时'),
          subtitle: Text(_labels[current]!),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final chosen = await showDialog<({CloseAction? action})>(
              context: context,
              builder: (context) => SimpleDialog(
                title: const Text('关闭窗口时'),
                children: [
                  for (final entry in _labels.entries)
                    ListTile(
                      title: Text(entry.value),
                      trailing: entry.key == current ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(context, (action: entry.key)),
                    ),
                ],
              ),
            );
            if (chosen == null) return;
            final choice = chosen.action;
            if (choice == null) {
              setDontAsk(false);
            } else {
              setAction(choice);
              setDontAsk(true);
            }
          },
        );
      },
    ),
  );
}
