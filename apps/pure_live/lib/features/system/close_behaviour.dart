import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/features/settings/settings_search.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

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
    title: Text(t.system.closeWindow),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.system.closeQuestion),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _remember,
          title: Text(t.system.dontAskAgain),
          subtitle: Text(t.system.changeInSettings),
          onChanged: (value) => setState(() => _remember = value ?? false),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, (action: CloseAction.minimize, remember: _remember)),
        child: Text(t.system.minimizeToTray),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (action: CloseAction.exit, remember: _remember)),
        child: Text(t.common.exit),
      ),
    ],
  );
}

/// "关闭窗口时" in 设置 › 通用 (Windows): ask every time, hide to the tray or
/// quit.
class CloseBehaviourTile extends StatelessWidget {
  /// Creates the tile.
  const new({super.key});

  static Map<CloseAction?, String> get _labels => {
    null: t.system.askEveryTime,
    CloseAction.minimize: t.system.minimizeToTray,
    CloseAction.exit: t.system.quitApp,
  };

  @override
  Widget build(BuildContext context) => SettingAnchor(id: Settings.closeAction.id, child: _tile());

  Widget _tile() => SettingBuilder<bool>(
    setting: Settings.closeDontAsk,
    builder: (context, dontAsk, setDontAsk) => SettingBuilder<CloseAction>(
      setting: Settings.closeAction,
      builder: (context, action, setAction) {
        final current = dontAsk ? action : null;
        return ListTile(
          title: Text(t.system.onClose),
          subtitle: Text(_labels[current]!),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final chosen = await showDialog<({CloseAction? action})>(
              context: context,
              builder: (context) => SimpleDialog(
                title: Text(t.system.onClose),
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
