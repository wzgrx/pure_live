import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/features/live_play/danmaku/danmaku_settings_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/record/record_panel.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/block_manager.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

/// The parts of [TvRoomSettingsPanel] (A17.4 c7–c10).
enum TvRoomSettingsTab {
  /// The danmaku settings: the phone's component, every item (c8).
  danmaku('danmaku_settings'),

  /// The block list: the phone's component (c9).
  shield('shield_title'),

  /// Recording: the phone's record panel (c10).
  record('record');

  new(this.labelKey);

  /// The tab's translation key.
  final String labelKey;
}

/// The TV room's play settings on the right (A17.4 c3, c7–c10, c15): Right,
/// the menu key or the info key opens it; tabs for the danmaku settings, the
/// block list and recording, each the phone's own component, so nothing is
/// missing and changes apply at once. The remote walks it by focus (the
/// TV's directional navigation); Back closes it.
class TvRoomSettingsPanel extends StatefulWidget {
  /// Creates the panel for [controller]'s room.
  const new({required this.controller, required this.onClose, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Closes the panel.
  final VoidCallback onClose;

  /// The panel's width in canvas pixels (c2).
  static const double width = 400;

  @override
  State<TvRoomSettingsPanel> createState() => _TvRoomSettingsPanelState();
}

class _TvRoomSettingsPanelState extends State<TvRoomSettingsPanel> {
  TvRoomSettingsTab _tab = TvRoomSettingsTab.danmaku;
  final FocusNode _first = FocusNode(debugLabel: 'tv room settings tabs');

  @override
  void initState() {
    super.initState();
    // The room's key node holds the focus: move it onto the tabs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabs = _first.traversalDescendants.where((node) => node.canRequestFocus).firstOrNull;
      (tabs ?? _first).requestFocus();
    });
  }

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  Widget _content() {
    final controller = widget.controller;
    return switch (_tab) {
      TvRoomSettingsTab.danmaku => RoomDanmakuSettings(controller: controller, inTab: true),
      TvRoomSettingsTab.shield => const DanmakuBlockManager(key: ValueKey('tv-room-shield')),
      TvRoomSettingsTab.record => RecordPanelBody(room: () => controller.room, qualities: () => controller.qualities),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    const tabs = TvRoomSettingsTab.values;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: FocusTraversalGroup(
        child: Container(
          key: const ValueKey('tv-room-settings'),
          width: scale.pxText(TvRoomSettingsPanel.width),
          color: palette.raised,
          padding: EdgeInsets.fromLTRB(scale.px(24), scale.px(28), scale.px(24), scale.px(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                i18n('tv_play_settings'),
                style: scale.font(TvTextSize.title, weight: FontWeight.w600, color: palette.text),
              ),
              SizedBox(height: scale.px(12)),
              Focus(
                focusNode: _first,
                canRequestFocus: false,
                skipTraversal: true,
                child: TvTabBar(
                  small: true,
                  tabs: [for (final tab in tabs) TvTab(id: tab.name, label: i18n(tab.labelKey))],
                  selected: tabs.indexOf(_tab),
                  onSelect: (index) => setState(() => _tab = tabs[index]),
                ),
              ),
              SizedBox(height: scale.px(8)),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: KeyedSubtree(key: ValueKey('tv-room-settings-${_tab.name}'), child: _content()),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: scale.px(8)),
                child: Text(
                  i18n('tv_play_settings_hint'),
                  style: scale.font(TvTextSize.small, color: palette.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
