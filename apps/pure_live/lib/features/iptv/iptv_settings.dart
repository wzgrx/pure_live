import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/iptv/iptv_import.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The automatic sync intervals offered (3.x).
const List<int> syncIntervalOptions = [2, 6, 12, 24, 48, 72];

/// Asks for the automatic sync interval (3.x `_showIntervalSelectionMenu`,
/// docs/A-界面设计/A13-网络电视和多画面界面/A13.1-网络电视管理 c17): one row per interval, the current one filled
/// and tinted; no buttons, a tap chooses. Null when dismissed.
Future<int?> chooseSyncInterval(BuildContext context, int current) => showAppOptionDialog<int>(
  context: context,
  title: i18n('select_sync_interval'),
  icon: AppIcons.syncInterval,
  selected: current,
  showCancel: false,
  options: [
    for (final hours in syncIntervalOptions)
      AppDialogOption(
        key: ValueKey('iptv-interval-$hours'),
        value: hours,
        label: i18n('iptv_every_hours', args: {'hour': '$hours'}),
      ),
  ],
);

/// The longest User-Agent accepted (3.x).
const int maxUserAgentLength = 500;

/// Edits the IPTV User-Agent (3.x `_UserAgentDialog`, docs/A-界面设计/A13-网络电视和多画面界面/A13.1-网络电视管理
/// c14): the field grows with its text (up to 8 lines; 3.x's "－ 144 px ＋"
/// bar is gone), a clear button, "留空使用默认请求头". The trimmed text, or
/// null when cancelled; an empty text means the player's default.
Future<String?> editUserAgent(BuildContext context, String current) => showAppDialog<String>(
  context: context,
  builder: (_) => _UserAgentDialog(initial: current),
);

class _UserAgentDialog extends StatefulWidget {
  const new({required this.initial});

  final String initial;

  @override
  State<_UserAgentDialog> createState() => _UserAgentDialogState();
}

class _UserAgentDialogState extends State<_UserAgentDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppDialog(
      title: i18n('edit_ua_title'),
      icon: AppIcons.userAgent,
      message: i18n('custom_ua_desc'),
      wide: true,
      autofocus: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 2),
          // The clear button sits in the box's top right corner, so it stays
          // put while the box grows.
          Stack(
            children: [
              TextField(
                key: const ValueKey('iptv-user-agent'),
                controller: _text,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                maxLength: maxUserAgentLength,
                style: context.textStyles.t13.copyWith(fontFamily: 'monospace', height: 1.5),
                decoration: iptvFieldDecoration(
                  context,
                  hint: 'Mozilla/5.0 …',
                  helper: i18n('iptv_ua_empty_hint'),
                ).copyWith(counterText: '', contentPadding: const EdgeInsets.fromLTRB(12, 12, 44, 12)),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  key: const ValueKey('iptv-user-agent-clear'),
                  tooltip: i18n('clear'),
                  color: scheme.onSurfaceVariant,
                  icon: const Icon(AppIcons.clearText, size: 20),
                  onPressed: _text.clear,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        const DialogCancelButton(),
        DialogActionButton(
          key: const ValueKey('iptv-user-agent-save'),
          label: i18n('save'),
          onPressed: () => Navigator.pop(context, _text.text.trim()),
        ),
      ],
    );
  }
}
