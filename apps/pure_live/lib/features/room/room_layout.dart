import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';

/// How the room is presented (principles §5.2): one enum, one video surface
/// that moves between layouts instead of being rebuilt.
enum RoomPresentation {
  /// Video on top (compact) or beside the chat panel (expanded and wider).
  inline,

  /// Video fills the window height; the info bar is hidden, chat stays optional.
  theater,

  /// Video fills the screen.
  fullscreen,
}

/// Lays out the video, the info section and the chat panel for the window
/// size and presentation. The same [video] widget instance is placed in every
/// layout, so switching layouts never recreates the player.
class RoomLayout extends StatelessWidget {
  const new({
    required this.presentation,
    required this.video,
    required this.info,
    required this.chat,
    this.chatVisible = true,
    super.key,
  });

  final RoomPresentation presentation;

  /// The single video surface with its controls.
  final Widget video;

  /// Streamer, title and actions.
  final Widget info;

  /// Chat list with pinned super chats.
  final Widget chat;

  /// Whether the chat panel is open (desktop can collapse it).
  final bool chatVisible;

  @override
  Widget build(BuildContext context) => WindowLayoutBuilder(
    builder: (context, layout) {
      final wide = layout.width.atLeast(WidthClass.expanded) && !layout.isShortLandscape;
      final keyedVideo = KeyedSubtree(key: const ValueKey('room-video'), child: video);
      if (presentation == RoomPresentation.fullscreen || layout.isShortLandscape) {
        return ColoredBox(color: Colors.black, child: keyedVideo);
      }
      if (!wide) {
        // Compact and medium: video full width on top, info and chat below.
        return Column(
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: keyedVideo),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: '弹幕'),
                        Tab(text: '直播间'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          chat,
                          SingleChildScrollView(child: info),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      final chatWidth = layout.width == WidthClass.expanded ? 320.0 : Sizes.chatWidth;
      final main = presentation == RoomPresentation.theater
          ? ColoredBox(color: Colors.black, child: keyedVideo)
          : ListView(
              children: [
                AspectRatio(aspectRatio: 16 / 9, child: keyedVideo),
                info,
              ],
            );
      return Row(
        children: [
          Expanded(child: main),
          if (chatVisible) ...[const VerticalDivider(width: 1), SizedBox(width: chatWidth, child: chat)],
        ],
      );
    },
  );
}
