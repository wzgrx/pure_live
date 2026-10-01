import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The two answers of the close dialog, as [Settings.exitChoose] stores
/// them (3.x `ExitSettingsController`).
enum CloseAction {
  /// Hide to the tray; minimize to the taskbar where there is no tray.
  minimize('minimize'),

  /// Leave the app.
  exit('exit');

  new(this.stored);

  /// The stored value.
  final String stored;

  /// The action of a stored value ([exit] for anything else, as 3.x).
  static CloseAction parse(String value) => value == minimize.stored ? minimize : exit;
}

/// The close dialog's answer: what to do, and whether to stop asking.
typedef CloseChoice = ({CloseAction action, bool remember});

/// Asks for a [CloseChoice]; null when the dialog was dismissed.
typedef CloseAsk = Future<CloseChoice?> Function({
  required bool tray,
  required int recording,
  required bool askRemember,
  required bool remember,
});

/// What closing a window does (3.x `Utils.showExitDialog`, `handleWindowClose`
/// and the tray's exit; docs/ui/compare/U.13 c7–c10):
///
/// - the main window's ✕ and Alt+F4 ([close]) do the remembered action when
///   "不再询问" is on, else ask; quitting while recording always asks (c9);
/// - an extra window's ✕ closes it, asking only while it records (c10);
/// - the tray's "退出应用" ([exitFromTray]) quits, asking while recording.
///
/// The answer is stored as 3.x did ([Settings.exitChoose],
/// [Settings.dontAskExit]) and put back when the window refused it.
final class WindowCloser {
  /// Creates the closer over the window's actions.
  new({
    required this.settings,
    required this.primary,
    required this.hasTray,
    required this.recordings,
    required this.ask,
    required this.hide,
    required this.minimize,
    required this.exit,
    required this.show,
    required this.failed,
  });

  /// The settings with the remembered answer.
  final SettingsStore settings;

  /// Whether this is the main window.
  final bool primary;

  /// Whether the tray icon is there (minimize hides the window to it).
  final bool Function() hasTray;

  /// How many rooms this window records now.
  final int Function() recordings;

  /// Shows the close dialog.
  final CloseAsk ask;

  /// Hides the window (to the tray).
  final Future<void> Function() hide;

  /// Minimizes the window to the taskbar.
  final Future<void> Function() minimize;

  /// Leaves the app (this window's process).
  final Future<void> Function() exit;

  /// Shows and focuses the window (before asking from the tray).
  final Future<void> Function() show;

  /// The window refused (3.x "窗口操作失败，请重试").
  final void Function() failed;

  Future<void>? _running;

  /// The title bar's ✕, Alt+F4 or the system's close; one at a time.
  Future<void> close() => _running ??= _close().whenComplete(() => _running = null);

  /// The tray's "退出应用"; one at a time.
  Future<void> exitFromTray() => _running ??= _exitFromTray().whenComplete(() => _running = null);

  Future<void> _close() async {
    final count = recordings();
    if (!primary) {
      if (count == 0) {
        await _do(CloseAction.exit);
        return;
      }
      final choice = await ask(tray: false, recording: count, askRemember: false, remember: false);
      if (choice != null) await _do(choice.action);
      return;
    }
    final remembered = CloseAction.parse(settings.get(Settings.exitChoose));
    final dontAsk = settings.get(Settings.dontAskExit);
    if (dontAsk && !(remembered == CloseAction.exit && count > 0)) {
      // 3.x: a remembered answer the window refused is asked again next time.
      if (!await _do(remembered)) await settings.set(Settings.dontAskExit, false);
      return;
    }
    final choice = await ask(tray: hasTray(), recording: count, askRemember: true, remember: dontAsk);
    if (choice == null) return;
    final before = <Setting<Object>, Object>{Settings.exitChoose: remembered.stored, Settings.dontAskExit: dontAsk};
    await settings.setAll({Settings.exitChoose: choice.action.stored, Settings.dontAskExit: choice.remember});
    if (!await _do(choice.action)) await settings.setAll(before);
  }

  Future<void> _exitFromTray() async {
    final count = recordings();
    if (count == 0) {
      await _do(CloseAction.exit);
      return;
    }
    await show();
    final choice = await ask(tray: hasTray(), recording: count, askRemember: false, remember: false);
    if (choice != null) await _do(choice.action);
  }

  Future<bool> _do(CloseAction action) async {
    try {
      if (action == CloseAction.exit) {
        await exit();
      } else {
        // Only the main window has the tray (c10).
        await (primary && hasTray() ? hide() : minimize());
      }
      return true;
    } on Object catch (error, stack) {
      log('Window close failed', name: 'Desktop', error: error, stackTrace: stack);
      failed();
      return false;
    }
  }
}

/// Shows the close dialog over [context] (Esc and a tap outside cancel).
Future<CloseChoice?> showCloseWindowDialog(
  BuildContext context, {
  required bool tray,
  required int recording,
  required bool askRemember,
  required bool remember,
}) => showDialog<CloseChoice>(
  context: context,
  builder: (_) => CloseWindowDialog(tray: tray, recording: recording, askRemember: askRemember, remember: remember),
);

/// The close dialog (3.x `_ExitDecisionDialog`; docs/ui/compare/U.13
/// c7–c9): "关闭窗口", the question, a red note while recording, "不再询问"
/// with where to change it later, and at the two ends "最小化到托盘" (or
/// "最小化" without a tray) and a red "退出应用".
class CloseWindowDialog extends StatefulWidget {
  /// Creates the dialog.
  const new({required this.tray, this.recording = 0, this.askRemember = true, this.remember = false, super.key});

  /// Whether the window hides to a tray icon (else it minimizes to the
  /// taskbar, and the words say so).
  final bool tray;

  /// How many rooms are recording (the red note when above 0).
  final int recording;

  /// Whether "不再询问" is offered (only for the main window's ✕).
  final bool askRemember;

  /// Whether "不再询问" starts ticked.
  final bool remember;

  /// The dialog's width (the design's 440).
  static const double width = 440;

  @override
  State<CloseWindowDialog> createState() => _CloseWindowDialogState();
}

class _CloseWindowDialogState extends State<CloseWindowDialog> {
  late bool _remember = widget.remember;

  void _answer(CloseAction action) =>
      Navigator.pop<CloseChoice>(context, (action: action, remember: widget.askRemember && _remember));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final styles = context.textStyles;
    final body = styles.t14.copyWith(color: scheme.onSurface, height: 1.5);
    final rememberRow = InkWell(
      key: const ValueKey('close-remember'),
      onTap: () => setState(() => _remember = !_remember),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: _remember, onChanged: (value) => setState(() => _remember = value ?? false)),
            Flexible(child: Text(i18n('dont_ask_again'), style: body)),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
    return DialogButtonsTheme(
      child: DialogKeys(
        child: Dialog(
          key: const ValueKey('close-dialog'),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: CloseWindowDialog.width),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          i18n('window_close'),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          i18n(widget.tray ? 'window_close_question' : 'window_close_question_taskbar'),
                          key: const ValueKey('close-question'),
                          style: body,
                        ),
                        if (widget.recording > 0) ...[
                          const SizedBox(height: 16),
                          _RecordingNote(count: widget.recording),
                        ],
                      ],
                    ),
                  ),
                  if (widget.askRemember)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(9, 8, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          rememberRow,
                          Padding(
                            // Under the words, past the box.
                            padding: const EdgeInsets.only(left: kMinInteractiveDimension),
                            child: Text(
                              i18n('window_close_hint'),
                              key: const ValueKey('close-hint'),
                              style: styles.t12.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 20, 24, 24),
                    // Two ends, as 3.x: minimize at the left, exit at the right.
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          key: const ValueKey('close-minimize'),
                          onPressed: () => _answer(CloseAction.minimize),
                          child: Text(i18n(widget.tray ? 'settings_exit_action_minimize' : 'minimize')),
                        ),
                        FilledButton(
                          key: const ValueKey('close-exit'),
                          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                          onPressed: () => _answer(CloseAction.exit),
                          child: Text(i18n('exit_app')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "正在录制 N 个直播间 / 退出会停止录制，已经录下的部分会保存。" in red on a
/// soft red ground (c9).
class _RecordingNote extends StatelessWidget {
  const new({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = context.textStyles.t14.copyWith(color: scheme.error, height: 1.5);
    return DecoratedBox(
      key: const ValueKey('close-recording'),
      decoration: BoxDecoration(
        color: LiveSemanticColors.recordingNote(theme.brightness),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: LiveSemanticColors.recording, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n('recording_rooms_count', args: {'count': '$count'}),
                    style: text.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(i18n('window_close_recording_desc'), style: text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
