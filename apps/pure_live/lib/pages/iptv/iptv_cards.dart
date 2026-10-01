import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// What the more menu of a card does.
enum IptvCardAction {
  /// Opens the address (browser) or file (system app).
  open,

  /// Copies the address.
  copy,

  /// Deletes the item.
  delete,
}

/// One playlist or guide source (3.x `iptv_manage.dart` `_buildItemCard`):
/// name, format badge, network or local, channel count, last update,
/// address; sync and automatic sync for network sources; "use" for guides.
class IptvSourceCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.id,
    required this.isGuide,
    required this.name,
    required this.address,
    required this.badge,
    required this.isRemote,
    required this.details,
    required this.autoUpdate,
    required this.busy,
    required this.blocked,
    required this.onSync,
    required this.onAutoUpdate,
    required this.onAction,
    this.selected = false,
    this.onSelect,
    super.key,
  });

  /// Id, for keys.
  final String id;

  /// Whether this is a guide source (else a playlist).
  final bool isGuide;

  /// Display name.
  final String name;

  /// URL or file path.
  final String address;

  /// Format badge (`M3U`, `TXT`, `XML` …).
  final String badge;

  /// Whether the address is a network address.
  final bool isRemote;

  /// Channel count and last update.
  final String details;

  /// Whether automatic sync is on.
  final bool autoUpdate;

  /// Whether an operation of this card runs.
  final bool busy;

  /// Whether the buttons are disabled (this card or the whole list busy).
  final bool blocked;

  /// Whether this guide is the one in use.
  final bool selected;

  /// Syncs it.
  final VoidCallback onSync;

  /// Turns automatic sync on or off.
  final ValueChanged<bool> onAutoUpdate;

  /// A more-menu action.
  final ValueChanged<IptvCardAction> onAction;

  /// Uses this guide; null for playlists.
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final styles = context.textStyles;
    final accent = isGuide ? Colors.orange : colors.primary;
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Leading(icon: isGuide ? Icons.event_note_rounded : Icons.playlist_play_rounded, color: accent, badge: badge),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: styles.t15Bold),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Chip(
                    text: i18n(isRemote ? 'network_tag' : 'local_tag'),
                    color: isRemote ? Colors.green : Colors.orange,
                  ),
                  if (selected) _Chip(text: i18n('iptv_guide_in_use'), color: colors.primary, filled: true),
                  Text(details, style: styles.t12Muted),
                ],
              ),
              const SizedBox(height: 4),
              Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: styles.t12Muted),
            ],
          ),
        ),
        PopupMenuButton<IptvCardAction>(
          key: ValueKey('iptv-more-$id'),
          enabled: !blocked,
          tooltip: i18n('iptv_more'),
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: onAction,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: IptvCardAction.open,
              child: _MenuRow(
                icon: Icons.open_in_new_rounded,
                text: i18n(isRemote ? 'iptv_open_url' : 'iptv_open_file'),
              ),
            ),
            PopupMenuItem(
              value: IptvCardAction.copy,
              child: _MenuRow(icon: Icons.copy_rounded, text: i18n('iptv_copy_address')),
            ),
          ],
        ),
      ],
    );
    final buttons = <Widget>[
      if (isRemote)
        TextButton.icon(
          key: ValueKey('iptv-sync-$id'),
          onPressed: blocked ? null : onSync,
          icon: busy
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync_rounded, size: 18),
          label: Text(i18n('sync')),
        ),
      if (onSelect != null && !selected)
        TextButton.icon(
          key: ValueKey('iptv-use-$id'),
          onPressed: blocked ? null : onSelect,
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text(i18n('iptv_use_guide')),
        ),
      TextButton.icon(
        key: ValueKey('iptv-remove-$id'),
        style: TextButton.styleFrom(foregroundColor: colors.error),
        onPressed: blocked ? null : () => onAction(IptvCardAction.delete),
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
        label: Text(i18n('webdav_delete')),
      ),
    ];
    final autoSync = isRemote
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(i18n('auto_sync'), style: styles.t13Medium),
              const SizedBox(width: 4),
              Switch(key: ValueKey('iptv-auto-$id'), value: autoUpdate, onChanged: blocked ? null : onAutoUpdate),
            ],
          )
        : null;
    return Card(
      key: ValueKey('iptv-card-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: selected ? colors.primaryContainer.withValues(alpha: 0.35) : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? colors.primary.withValues(alpha: 0.4) : theme.dividerColor.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 460 || autoSync == null) {
                  return Row(
                    children: [
                      Expanded(child: Wrap(spacing: 4, children: buttons)),
                      ?autoSync,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(spacing: 4, children: buttons),
                    Align(alignment: AlignmentDirectional.centerEnd, child: autoSync),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Leading extends StatelessWidget {
  const new({required this.icon, required this.color, required this.badge});

  final IconData icon;
  final Color color;
  final String badge;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: color),
      ),
      Positioned(
        right: -6,
        bottom: -4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
          ),
          child: Text(
            badge,
            style: context.textStyles.t11Bold.copyWith(color: Colors.white, letterSpacing: 0.2, height: 1.2),
          ),
        ),
      ),
    ],
  );
}

class _Chip extends StatelessWidget {
  const new({required this.text, required this.color, this.filled = false});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: context.textStyles.t11Bold.copyWith(color: filled ? Theme.of(context).colorScheme.onPrimary : color),
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(text)]);
}

/// A stat of the overview card.
class IptvStat extends StatelessWidget {
  /// Creates the stat.
  const new({required this.icon, required this.value, required this.label, super.key});

  /// Icon.
  final IconData icon;

  /// The number.
  final String value;

  /// What it counts.
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: colors.primary),
        ),
        const SizedBox(height: 8),
        Text(value, style: context.textStyles.t16Bold),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center, style: context.textStyles.t12Muted),
      ],
    );
  }
}

/// A notice card: an icon, a title, text and actions (load errors, the
/// empty sections, "IPTV is not enabled").
class IptvNotice extends StatelessWidget {
  /// Creates the notice.
  const new({required this.icon, required this.title, this.text, this.actions = const [], this.color, super.key});

  /// Icon.
  final IconData icon;

  /// Title.
  final String title;

  /// Explanation.
  final String? text;

  /// Buttons.
  final List<Widget> actions;

  /// Accent colour (the primary colour when null).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = color ?? colors.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: accent.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.textStyles.t14Bold),
                  if (text != null) ...[const SizedBox(height: 4), Text(text!, style: context.textStyles.t13Muted)],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4, children: actions),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
