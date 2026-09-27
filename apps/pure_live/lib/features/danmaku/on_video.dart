import 'package:flutter/widgets.dart';
import 'package:live_danmaku/live_danmaku.dart' as dm;
import 'package:live_ui/live_ui.dart';

/// What the room feeds the on-video layer. The names are those of
/// `live_ui`'s [DanmakuController], which implements it through
/// [ControllerOnVideo]; tests use a recording fake.
abstract interface class OnVideoDanmaku {
  /// Queues a batch of items (REN-7: only chat, and only while playing).
  void addAll(Iterable<DanmakuItem> items);

  /// Removes everything waiting and on screen (room change, danmaku off).
  void clear();

  /// Removes the chat lines [test] matches, waiting and on screen (a block
  /// applies to what is already flying, FLT-2).
  void removeWhere(bool Function(dm.DanmakuChat chat) test);

  /// Freezes the layer for [reason] (`#video`, `#menu`); reasons stack.
  void pause(Object reason);

  /// Releases [reason].
  void resume(Object reason);

  /// The item under a global position, for tap and long-press actions
  /// (REN-8); its `data` is the [dm.DanmakuChat].
  DanmakuHit? itemAtGlobal(Offset globalPosition);
}

/// [OnVideoDanmaku] over `live_ui`'s renderer.
final class ControllerOnVideo implements OnVideoDanmaku {
  new(this.controller);

  /// The renderer's controller; one per surface.
  final DanmakuController controller;

  @override
  void addAll(Iterable<DanmakuItem> items) => controller.addAll(items);

  @override
  void clear() => controller.clear();

  @override
  void removeWhere(bool Function(dm.DanmakuChat chat) test) =>
      controller.removeWhere((item) => item.data is dm.DanmakuChat && test(item.data! as dm.DanmakuChat));

  @override
  void pause(Object reason) => controller.pause(reason);

  @override
  void resume(Object reason) => controller.resume(reason);

  @override
  DanmakuHit? itemAtGlobal(Offset globalPosition) => controller.itemAtGlobal(globalPosition);
}

/// Pause reason while playback is not playing (REN-7: positions freeze).
const Object pausedForVideo = #video;

/// Pause reason while a danmaku action menu is open (REN-8).
const Object pausedForMenu = #menu;

/// The on-video item for a chat line: its RGB colour made opaque, its local
/// position and lifetime, and the line itself as the hit-test payload.
DanmakuItem onVideoItem(dm.DanmakuChat chat) {
  final style = chat.style;
  return DanmakuItem(
    chat.text,
    color: Color(0xFF000000 | chat.color),
    kind: switch (style?.position) {
      dm.DanmakuPosition.top => DanmakuKind.top,
      dm.DanmakuPosition.bottom => DanmakuKind.bottom,
      _ => DanmakuKind.scroll,
    },
    isLocal: chat.isLocal,
    duration: style?.duration,
    data: chat,
  );
}

/// The chat line behind a hit, when it is one.
dm.DanmakuChat? chatOfHit(DanmakuHit? hit) => switch (hit?.item.data) {
  final dm.DanmakuChat chat => chat,
  _ => null,
};

/// The on-video layer between the video and the controls (LAY-2). It takes
/// no pointers and no focus (KEY-1); the player's gesture layer hit-tests
/// through [DanmakuController.itemAtGlobal]. Not built while danmaku is
/// hidden, so its texts are freed (REN-9).
class DanmakuOverlay extends StatelessWidget {
  const new({required this.controller, required this.visible, super.key});

  final DanmakuController controller;
  final bool visible;

  @override
  Widget build(BuildContext context) =>
      visible ? IgnorePointer(child: DanmakuView(controller: controller)) : const SizedBox.shrink();
}
