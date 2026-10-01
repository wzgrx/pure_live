import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The automatic sync intervals offered (3.x).
const List<int> syncIntervalOptions = [2, 6, 12, 24, 48, 72];

/// Asks for the automatic sync interval (3.x `_showIntervalSelectionMenu`);
/// null when dismissed.
Future<int?> chooseSyncInterval(BuildContext context, int current) => showDialog<int>(
  context: context,
  builder: (dialogContext) {
    final colors = Theme.of(dialogContext).colorScheme;
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      title: Text(i18n('select_sync_interval'), style: dialogContext.textStyles.t16Bold),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final hours in syncIntervalOptions)
              ListTile(
                key: ValueKey('iptv-interval-$hours'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                selected: hours == current,
                selectedTileColor: colors.primary.withValues(alpha: 0.08),
                leading: Icon(
                  hours == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: hours == current ? colors.primary : Theme.of(dialogContext).hintColor,
                ),
                title: Text(i18n('iptv_every_hours', args: {'hour': '$hours'})),
                onTap: () => Navigator.pop(dialogContext, hours),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(i18n('cancel')))],
    );
  },
);

/// The longest User-Agent accepted (3.x).
const int maxUserAgentLength = 500;

/// Edits the IPTV User-Agent (3.x `_UserAgentDialog`); the trimmed text, or
/// null when cancelled. An empty text means the player's default.
Future<String?> editUserAgent(BuildContext context, String current) => showDialog<String>(
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
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
    title: Text(i18n('edit_ua_title'), style: context.textStyles.t16Bold),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(i18n('custom_ua_desc'), style: context.textStyles.t13Muted),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('iptv-user-agent'),
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: maxUserAgentLength,
            style: context.textStyles.t13.copyWith(fontFamily: 'monospace'),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'Mozilla/5.0 …',
              helperText: i18n('iptv_ua_empty_hint'),
              helperMaxLines: 2,
              suffixIcon: IconButton(
                tooltip: i18n('clear'),
                icon: const Icon(Icons.clear_rounded),
                onPressed: _text.clear,
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
      FilledButton(
        key: const ValueKey('iptv-user-agent-save'),
        onPressed: () => Navigator.pop(context, _text.text.trim()),
        child: Text(i18n('confirm')),
      ),
    ],
  );
}
