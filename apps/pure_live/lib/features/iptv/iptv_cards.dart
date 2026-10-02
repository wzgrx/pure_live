import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// What the more menu of a card does (docs/T11/T11a/T11a.4 c5).
enum IptvCardAction {
  /// Opens the address (browser) or file (system app).
  open,

  /// Copies the address.
  copy,
}

/// The cards' buttons sit in one row from this card width on (wide screens,
/// landscape phones); narrower cards put sync and delete in a row and the
/// automatic sync switch under them (3.x split at 680).
const double iptvCardOneRowWidth = 520;

/// One playlist or guide source (3.x `iptv_manage.dart` `_buildItemCard`,
/// docs/T11/T11a/T11a.4 c3–c6): the icon with the format badge, the name,
/// "网络 / 本地", the channel count and last update, the address; "更多"
/// (open, copy; a right click opens it too); sync, delete and automatic
/// sync for network sources, delete only for local ones.
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
    required this.onDelete,
    required this.onAutoUpdate,
    required this.onAction,
    this.inUse = false,
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

  /// Format badge (`M3U`, `TXT`, `XML.GZ` …).
  final String badge;

  /// Whether the address is a network address.
  final bool isRemote;

  /// Channel count and last update.
  final String details;

  /// Whether automatic sync is on.
  final bool autoUpdate;

  /// Whether a sync of this card runs.
  final bool busy;

  /// Whether the buttons are disabled (this card or the whole list busy).
  final bool blocked;

  /// Whether this guide is the one in use ("使用中", a primary outline).
  final bool inUse;

  /// Syncs it.
  final VoidCallback onSync;

  /// Deletes it (after asking).
  final VoidCallback onDelete;

  /// Turns automatic sync on or off.
  final ValueChanged<bool> onAutoUpdate;

  /// A more-menu action.
  final ValueChanged<IptvCardAction> onAction;

  Future<void> _menu(BuildContext context, RelativeRect position) async {
    final action = await showMenu<IptvCardAction>(
      context: context,
      position: position,
      constraints: const BoxConstraints(minWidth: 200),
      items: [
        PopupMenuItem(
          key: ValueKey('iptv-open-$id'),
          value: IptvCardAction.open,
          child: _MenuRow(icon: AppIcons.openExternal, text: i18n(isRemote ? 'iptv_open_url' : 'iptv_open_file')),
        ),
        PopupMenuItem(
          key: ValueKey('iptv-copy-$id'),
          value: IptvCardAction.copy,
          child: _MenuRow(icon: AppIcons.copy, text: i18n('iptv_copy_address')),
        ),
      ],
    );
    if (action != null) onAction(action);
  }

  /// The menu under the more button.
  void _menuAtButton(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(buttonContext).overlay!.context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset(0, box.size.height), ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    _menu(buttonContext, RelativeRect.fromRect(rect, Offset.zero & overlay.size)).ignore();
  }

  /// The menu where the card was right-clicked (desktop).
  void _menuAt(BuildContext context, Offset global) {
    final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final at = overlay.globalToLocal(global);
    _menu(context, RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size)).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final muted = styles.t12.copyWith(color: scheme.onSurfaceVariant);
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Leading(isGuide: isGuide, badge: badge),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: styles.t15.emphasis),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IptvTag(
                    key: ValueKey('iptv-origin-tag-$id'),
                    icon: isRemote ? AppIcons.networkSource : AppIcons.localSource,
                    text: i18n(isRemote ? 'network_tag' : 'local_tag'),
                  ),
                  if (inUse) IptvTag(key: ValueKey('iptv-in-use-$id'), text: i18n('iptv_guide_in_use'), strong: true),
                  Text(details, style: muted.tabular),
                ],
              ),
              const SizedBox(height: 4),
              Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -6),
          child: Builder(
            builder: (buttonContext) => IconButton(
              key: ValueKey('iptv-more-$id'),
              tooltip: i18n('iptv_more'),
              color: scheme.onSurfaceVariant,
              onPressed: () => _menuAtButton(buttonContext),
              icon: const Icon(AppIcons.more),
            ),
          ),
        ),
      ],
    );
    final sync = _CardButton(
      key: ValueKey('iptv-sync-$id'),
      icon: AppIcons.syncOne,
      label: i18n('sync'),
      busy: busy,
      onPressed: blocked ? null : onSync,
    );
    final delete = _CardButton(
      key: ValueKey('iptv-remove-$id'),
      icon: AppIcons.delete,
      label: i18n('delete'),
      destructive: true,
      onPressed: blocked ? null : onDelete,
    );
    final autoSync = _AutoSyncRow(id: id, value: autoUpdate, onChanged: blocked ? null : onAutoUpdate);
    return GestureDetector(
      onSecondaryTapUp: (details) => _menuAt(context, details.globalPosition),
      child: Container(
        key: ValueKey('iptv-card-$id'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 4, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: inUse ? Border.all(color: scheme.primary, width: 1.5) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            Padding(
              padding: const EdgeInsets.only(top: 12, right: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!isRemote) return Row(children: [Expanded(child: delete)]);
                  if (constraints.maxWidth >= iptvCardOneRowWidth) {
                    return Row(
                      key: ValueKey('iptv-actions-row-$id'),
                      children: [
                        Expanded(flex: 10, child: sync),
                        const SizedBox(width: 8),
                        Expanded(flex: 13, child: autoSync),
                        const SizedBox(width: 8),
                        Expanded(flex: 10, child: delete),
                      ],
                    );
                  }
                  return Column(
                    key: ValueKey('iptv-actions-column-$id'),
                    children: [
                      Row(
                        children: [
                          Expanded(child: sync),
                          const SizedBox(width: 8),
                          Expanded(child: delete),
                        ],
                      ),
                      const SizedBox(height: 8),
                      autoSync,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The icon box with the format badge (3.x `_buildLeading`): playlists in
/// the primary container, guides in the warm container; the badge in the
/// container's ink.
class _Leading extends StatelessWidget {
  const new({required this.isGuide, required this.badge});

  final bool isGuide;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isGuide ? LiveSemanticColors.warmContainer(scheme.brightness) : scheme.primaryContainer;
    final ink = isGuide ? LiveSemanticColors.onWarmContainer(scheme.brightness) : scheme.onPrimaryContainer;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
          child: Icon(isGuide ? AppIcons.guide : AppIcons.playlist, color: ink),
        ),
        Positioned(
          right: -6,
          bottom: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.surfaceContainerLow, width: 2),
            ),
            child: Text(badge, style: context.textStyles.t11Bold.copyWith(color: background, height: 1.25)),
          ),
        ),
      ],
    );
  }
}

/// A small grey tag on a card ("网络", "本地"), or the primary "使用中".
class IptvTag extends StatelessWidget {
  /// Creates the tag.
  const new({required this.text, this.icon, this.strong = false, super.key});

  /// The words.
  final String text;

  /// An icon before them.
  final IconData? icon;

  /// The primary colour ("使用中").
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = strong ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: strong ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: ink), const SizedBox(width: 3)],
          Text(
            text,
            style: context.textStyles.t12.copyWith(color: ink, fontWeight: FontWeight.w600, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// "同步" or "删除" on a card (3.x `_buildActionButton`): 48 high, a tinted
/// background; a spinner while it syncs.
class _CardButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = destructive ? scheme.error : scheme.primary;
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: ink,
        backgroundColor: ink.withValues(alpha: 0.08),
        disabledForegroundColor: ink.withValues(alpha: 0.38),
        disabledBackgroundColor: ink.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: context.textStyles.t14.emphasis,
      ),
      icon: busy
          ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: ink))
          : Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

/// The automatic sync switch of a card (3.x: `repeat_line` and a switch in a
/// tinted box).
class _AutoSyncRow extends StatelessWidget {
  const new({required this.id, required this.value, required this.onChanged});

  final String id;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final change = onChanged;
    return Material(
      color: scheme.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: change == null ? null : () => change(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
            child: Row(
              children: [
                Icon(AppIcons.autoSync, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(i18n('auto_sync'), style: context.textStyles.t14)),
                Switch(key: ValueKey('iptv-auto-$id'), value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(width: 12),
      Text(text, style: context.textStyles.t14),
    ],
  );
}

/// The counts at the top (docs/T11/T11a/T11a.4 c8): playlists, channels,
/// guides, 20 px tabular numbers.
class IptvStats extends StatelessWidget {
  /// Creates the counts.
  const new({required this.playlists, required this.channels, required this.guides, super.key});

  /// Saved playlists.
  final String playlists;

  /// Channels of all playlists.
  final String channels;

  /// Saved guides.
  final String guides;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget stat(String key, String value, String label) => Expanded(
      child: Column(
        key: ValueKey(key),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: context.textStyles.t20.emphasis.tabular),
          const SizedBox(height: 2),
          Text(label, style: context.textStyles.t12.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
    return Container(
      key: const ValueKey('iptv-stats'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          stat('iptv-stat-playlists', playlists, i18n('iptv_stat_playlists')),
          stat('iptv-stat-channels', channels, i18n('iptv_stat_channels')),
          stat('iptv-stat-guides', guides, i18n('iptv_stat_guides')),
        ],
      ),
    );
  }
}

/// "正在同步网络来源 1 / 3" and its bar, in the place of the counts while
/// every source syncs (c7).
class IptvSyncProgress extends StatelessWidget {
  /// Creates the progress.
  const new({required this.done, required this.total, super.key});

  /// Sources finished.
  final int done;

  /// Sources to sync.
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('iptv-sync-progress'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(i18n('iptv_sync_all_running'), style: context.textStyles.t14)),
              Text(
                '${done < total ? done + 1 : total} / $total',
                style: context.textStyles.t14.copyWith(color: scheme.onSurfaceVariant).tabular,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: total == 0 ? null : done / total, minHeight: 4),
          ),
        ],
      ),
    );
  }
}

/// A state card (c16): an icon, a title, text and buttons; [centered] for
/// the empty states, a leading icon otherwise (read failure, the default
/// guide); [warning] paints it as a warning (IPTV not enabled).
class IptvStateCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.title,
    this.icon,
    this.leading,
    this.text,
    this.actions = const [],
    this.centered = false,
    this.iconColor,
    this.warning = false,
    super.key,
  });

  /// The icon.
  final IconData? icon;

  /// A widget in the icon's place (a spinner).
  final Widget? leading;

  /// Its colour (the error colour for failures).
  final Color? iconColor;

  /// Title.
  final String title;

  /// Explanation.
  final String? text;

  /// Buttons.
  final List<Widget> actions;

  /// The empty-state layout: the icon above, everything centred.
  final bool centered;

  /// The warning background and colour.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warn = LiveSemanticColors.warning(scheme.brightness);
    final accent = warning ? warn : iconColor ?? scheme.onSurfaceVariant;
    final glyph = leading ?? (icon == null ? null : Icon(icon, size: centered ? 32 : 22, color: accent));
    final titleStyle = (centered || !warning ? context.textStyles.t15 : context.textStyles.t14).emphasis;
    final body = text == null
        ? null
        : Text(
            text!,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: context.textStyles.t13.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
          );
    final decoration = BoxDecoration(
      color: warning ? warn.withValues(alpha: 0.1) : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    );
    if (centered) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        decoration: decoration,
        child: Column(
          children: [
            ?glyph,
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: titleStyle),
            if (body != null) ...[const SizedBox(height: 6), body],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: decoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (glyph != null) ...[
            Padding(padding: const EdgeInsets.only(top: 1), child: glyph),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle),
                if (body != null) ...[const SizedBox(height: 4), body],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, runSpacing: 4, children: actions),
                ] else
                  const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The page while the IPTV tables are read for the first time: a static
/// skeleton of the counts, a group and a card (no shimmer, UI_PLAN §9.3).
class IptvSkeleton extends StatelessWidget {
  /// Creates the skeleton.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget bone(double? width, double height, double radius) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(radius)),
    );
    return Column(
      key: const ValueKey('iptv-skeleton'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bone(double.infinity, 74, 16),
        const SizedBox(height: 20),
        bone(70, 12, 8),
        const SizedBox(height: 10),
        bone(double.infinity, 72, 20),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bone(48, 48, 14),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(widthFactor: 0.5, child: bone(null, 14, 8)),
                    const SizedBox(height: 8),
                    FractionallySizedBox(widthFactor: 0.8, child: bone(null, 12, 8)),
                    const SizedBox(height: 8),
                    FractionallySizedBox(widthFactor: 0.9, child: bone(null, 12, 8)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
