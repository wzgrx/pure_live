import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';

// The room menu on the picture (docs/A-界面设计/A07-直播间界面/A07.23-横屏右上角菜单升级): the
// fullscreen bars' four-square button opens it as a room panel, where the
// other landscape panels are, instead of the small light menu squeezed into
// the corner over the picture.

/// The smallest height of a row of [RoomMenuPanel]: the six rows of the
/// landscape menu, the gaps and the header fit a 400-high phone (the K90 on
/// its side) without scrolling.
const double roomMenuRowHeight = 52;

/// The gap between the groups of [RoomMenuPanel].
const double roomMenuGroupGap = 8;

/// The room menu as a room panel ([RoomPanelKind.menu]): the same groups,
/// rows, icons and second lines as the small menu ([roomMenuItems]), each
/// group a rounded card, each row 52 high with a 24-point icon, the name in
/// 15 and its state in 13 under it; a row that opens a panel ends in ›.
///
/// A row that opens a panel (sleep timer, volume, stream address, cast,
/// switch room, local interaction) puts that panel in this one's place; a
/// row that does something at once (share, open in the platform's app, a
/// new window) closes the panel first. "画面比例" opens its small menu next
/// to the row and closes the panel once a fit is picked.
class RoomMenuPanel extends ConsumerWidget {
  /// Creates the panel.
  const new({
    required this.controller,
    required this.onClose,
    this.onBars = const {},
    this.dragToClose = false,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// Closes the panel.
  final VoidCallback onClose;

  /// What the bars around the menu button already show ([menuEntriesOnBars]).
  final Set<RoomMenuEntry> onBars;

  /// A downward drag on the header closes it (portrait fullscreen).
  final bool dragToClose;

  Future<void> _choose(BuildContext row, WidgetRef ref, RoomMenuEntry entry) async {
    if (roomMenuOpensPanel(entry)) {
      // Opens in this panel's place.
      await RoomMenuButton.run(row, ref, controller, entry);
      return;
    }
    if (entry == RoomMenuEntry.videoFit) {
      final settings = ref.read(storeProvider).settings;
      final before = videoFitIndexOf(settings);
      await showVideoFitMenu(row, settings);
      if (videoFitIndexOf(settings) != before) onClose();
      return;
    }
    onClose();
    await RoomMenuButton.run(row, ref, controller, entry);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The rows' second lines and the local interaction's row follow these.
    watchSetting(ref, Settings.videoFitIndex);
    watchSetting(ref, Settings.localInteractionEnabled);
    final settings = ref.read(storeProvider).settings;
    return RoomSidePanel(
      key: const ValueKey('room-menu-panel'),
      title: i18n('menu'),
      onClose: onClose,
      dragToClose: dragToClose,
      child: ListenableBuilder(
        // The stage (cast and the stream address) and the sleep timer.
        listenable: controller,
        builder: (context, _) {
          final groups = roomMenuItems(controller, settings, onBars: onBars);
          return ListView(
            key: const ValueKey('room-menu-list'),
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            children: [
              for (final (index, group) in groups.indexed) ...[
                if (index > 0) const SizedBox(height: roomMenuGroupGap),
                PanelCard(
                  key: ValueKey('room-menu-group-$index'),
                  children: [
                    Material(
                      type: MaterialType.transparency,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in group)
                            Builder(
                              builder: (row) =>
                                  RoomMenuRow(item: item, onTap: () => unawaited(_choose(row, ref, item.entry))),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One row of [RoomMenuPanel] (key `room-menu-<entry>`, as in the small
/// menu): the icon in the variant ink, the name in 15 and the second line
/// in 13 under it (both wrap with large text), › when it opens a panel;
/// greyed and not tappable when the item is not `enabled`.
class RoomMenuRow extends StatelessWidget {
  /// Creates the row.
  const new({required this.item, required this.onTap, super.key});

  /// What the row shows.
  final RoomMenuItem item;

  /// Chooses it.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final off = scheme.onSurface.withValues(alpha: 0.38);
    final enabled = item.enabled;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        child: InkWell(
          key: ValueKey('room-menu-${item.entry.name}'),
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: roomMenuRowHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              child: Row(
                children: [
                  Icon(item.icon, size: 24, color: enabled ? scheme.onSurfaceVariant : off),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.label,
                          style: theme.textTheme.bodyLarge?.regular.copyWith(
                            fontSize: 15,
                            color: enabled ? scheme.onSurface : off,
                          ),
                        ),
                        if (item.description case final description?)
                          Text(
                            description,
                            key: ValueKey('room-menu-${item.entry.name}-description'),
                            style: theme.textTheme.bodyMedium?.regular.copyWith(
                              color: enabled ? scheme.onSurfaceVariant : off,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (roomMenuOpensPanel(item.entry)) ...[
                    const SizedBox(width: 8),
                    Icon(AppIcons.forward, size: 20, color: enabled ? scheme.onSurfaceVariant : off),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
